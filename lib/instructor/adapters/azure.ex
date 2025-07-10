defmodule Instructor.Adapters.Azure do
  @moduledoc """
  Documentation for `Instructor.Adapters.Azure`.
  """
  @behaviour Instructor.Adapter
  @supported_modes [:tools, :json, :md_json, :json_schema]

  @default_model "o3-mini"

  alias Instructor.JSONSchema
  alias Instructor.SSEStreamParser

  @impl true
  def chat_completion(params, user_config \\ nil) do
    config = config(user_config, params)

    # Peel off instructor only parameters
    {_, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :max_retries)
    {mode, params} = Keyword.pop(params, :mode)
    stream = Keyword.get(params, :stream, false)
    params = Enum.into(params, %{})

    if mode not in @supported_modes do
      raise "Unsupported OpenAI mode #{mode}. Supported modes: #{inspect(@supported_modes)}"
    end

    params =
      case params do
        # OpenAI's json_schema mode doesn't support format or pattern attributes
        %{response_format: %{json_schema: %{schema: _schema}}} ->
          update_in(params, [:response_format, :json_schema, :schema], &normalize_json_schema/1)

        _ ->
          params
      end

    if stream do
      do_streaming_chat_completion(mode, params, config)
    else
      do_chat_completion(mode, params, config)
    end
  end

  defp normalize_json_schema(schema) do
    JSONSchema.traverse_and_update(schema, fn
      %{"type" => _} = x when is_map_key(x, "format") or is_map_key(x, "pattern") ->
        {format, x} = Map.pop(x, "format")
        {pattern, x} = Map.pop(x, "pattern")

        Map.update(x, "description", "", fn description ->
          "#{description} (format: #{format}, pattern: #{pattern})"
        end)

      x ->
        x
    end)
  end

  @impl true
  def reask_messages(raw_response, params, _config) do
    reask_messages_for_mode(params[:mode], raw_response)
  end

  defp reask_messages_for_mode(:tools, %{
         "choices" => [
           %{
             "message" =>
               %{
                 "tool_calls" => [
                   %{"id" => tool_call_id, "function" => %{"name" => name, "arguments" => args}} =
                     function
                 ]
               } = message
           }
         ]
       }) do
    [
      Map.put(message, "content", function |> Jason.encode!())
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end),
      %{
        role: "tool",
        tool_call_id: tool_call_id,
        name: name,
        content: args
      }
    ]
  end

  defp reask_messages_for_mode(_mode, _raw_response) do
    []
  end

  defp do_streaming_chat_completion(mode, params, config) do
    pid = self()
    options = http_options(config)
    ref = make_ref()

    Stream.resource(
      fn ->
        Task.async(fn ->
          options =
            Keyword.merge(options, [
              auth_header(config),
              json: params,
              into: fn {:data, data}, {req, resp} ->
                send(pid, {ref, data})
                {:cont, {req, resp}}
              end
            ])

          Req.post(url(config), options)
          send(pid, {ref, :done})
        end)
      end,
      fn task ->
        receive do
          {^ref, :done} ->
            {:halt, task}

          {^ref, data} ->
            {[data], task}
        after
          45_000 ->
            raise "Timeout waiting for LLM call to receive streaming data"
        end
      end,
      fn _ -> nil end
    )
    |> SSEStreamParser.parse()
    |> Stream.map(fn chunk ->
      parse_stream_chunk_for_mode(mode, chunk)
    end)
  end

  defp do_chat_completion(mode, params, config) do
    options = Keyword.merge(http_options(config), [auth_header(config), json: params])

    with {:ok, %Req.Response{status: 200, body: body} = response} <-
           Req.post(url(config), options),
         {:ok, content} <- parse_response_for_mode(mode, body) do
      {:ok, response, content}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Unexpected HTTP response code: #{status}\n#{inspect(body)}"}

      e ->
        e
    end
  end

  defp parse_response_for_mode(:tools, %{
         "choices" => [
           %{"message" => %{"tool_calls" => [%{"function" => %{"arguments" => args}}]}}
         ]
       }),
       do: Jason.decode(args)

  defp parse_response_for_mode(:md_json, %{"choices" => [%{"message" => %{"content" => content}}]}),
       do: Jason.decode(content)

  defp parse_response_for_mode(:json, %{"choices" => [%{"message" => %{"content" => content}}]}),
    do: Jason.decode(content)

  defp parse_response_for_mode(:json_schema, %{
         "choices" => [%{"message" => %{"content" => content}}]
       }),
       do: Jason.decode(content)

  defp parse_response_for_mode(mode, response) do
    {:error, "Unsupported OpenAI mode #{mode} with response #{inspect(response)}"}
  end

  defp parse_stream_chunk_for_mode(:md_json, %{"choices" => [%{"delta" => %{"content" => chunk}}]}),
       do: chunk

  defp parse_stream_chunk_for_mode(:json, %{"choices" => [%{"delta" => %{"content" => chunk}}]}),
    do: chunk

  defp parse_stream_chunk_for_mode(:json_schema, %{
         "choices" => [%{"delta" => %{"content" => chunk}}]
       }),
       do: chunk

  defp parse_stream_chunk_for_mode(:tools, %{
         "choices" => [
           %{"delta" => %{"tool_calls" => [%{"function" => %{"arguments" => chunk}}]}}
         ]
       }),
       do: chunk

  defp parse_stream_chunk_for_mode(:tools, %{
         "choices" => [
           %{"delta" => delta}
         ]
       }) do
    case delta do
      nil -> ""
      %{} -> ""
      %{"content" => chunk} -> chunk
    end
  end

  defp parse_stream_chunk_for_mode(_, %{"choices" => []}), do: ""

  defp parse_stream_chunk_for_mode(_, %{"choices" => [%{"finish_reason" => "stop"}]}), do: ""

  defp url(config), do: api_url(config) <> api_path(config)
  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_path(config), do: Keyword.fetch!(config, :api_path)

  defp api_key(config) do
    case Keyword.fetch!(config, :api_key) do
      string when is_binary(string) -> string
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp auth_header(config) do
    case Keyword.fetch!(config, :auth_mode) do
      # https://learn.microsoft.com/en-us/azure/ai-services/openai/reference
      :api_key_header -> {:headers, %{"api-key" => api_key(config)}}
      _ -> {:auth, {:bearer, api_key(config)}}
    end
  end

  defp http_options(config), do: Keyword.fetch!(config, :http_options)

  defp config(nil, params), do: config(Application.get_env(:instructor, :azure, []), params)

  defp config(base_config, params) do
    model = Keyword.get(params, :model, @default_model)

    default_config =
      Keyword.merge(
        [
          api_url: System.fetch_env!("AZURE_API_URL"),
          api_path:
            "/openai/deployments/#{model}/chat/completions?api-version=2025-01-01-preview",
          api_key: System.fetch_env!("AZURE_API_KEY"),
          auth_mode: :api_key_header,
          http_options: [receive_timeout: 60_000]
        ],
        Application.get_env(:instructor, :azure, [])
      )

    Keyword.merge(default_config, base_config)
  end
end
