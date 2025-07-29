defmodule Instructor.Adapters.OpenAI do
  @moduledoc """
  Documentation for `Instructor.Adapters.OpenAI`.
  """
  @behaviour Instructor.Adapter
  @supported_modes [:tools, :json, :md_json, :json_schema]

  # 2 minutes
  @default_timeout 120_000
  # 20 seconds between chunks
  @default_stream_timeout 20_000

  alias Instructor.JSONSchema
  alias Instructor.SSEStreamParser
  alias Instructor.Utils

  @impl true
  def chat_completion(params, user_config \\ nil) do
    config = config(user_config)

    # Peel off instructor only parameters
    {_, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :max_retries)
    {mode, params} = Keyword.pop(params, :mode)
    {timeout, params} = Keyword.pop(params, :timeout, @default_timeout)
    {stream_timeout, params} = Keyword.pop(params, :stream_timeout, @default_stream_timeout)
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
      do_streaming_chat_completion(mode, params, config, timeout, stream_timeout)
    else
      do_chat_completion(mode, params, config, timeout)
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
      Map.put(message, "content", function |> JSON.encode!())
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

  defp do_streaming_chat_completion(mode, params, config, initial_timeout, stream_timeout) do
    pid = self()
    options = http_options(config, initial_timeout)
    ref = make_ref()

    Stream.resource(
      fn ->
        task =
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

        # Return task with initial state
        {task, :initial}
      end,
      fn
        # Initial state - waiting for first chunk
        {task, :initial} ->
          receive do
            {^ref, :done} ->
              {:halt, task}

            {^ref, data} ->
              # Got first chunk, switch to streaming state
              dbg(data_initial: data)
              {[data], {task, :streaming}}
          after
            initial_timeout ->
              raise "Timeout waiting for LLM call to start streaming"
          end

        # Streaming state - shorter timeout between chunks
        {task, :streaming} ->
          receive do
            {^ref, :done} ->
              {:halt, task}

            {^ref, data} ->
              {[data], {task, :streaming}}
          after
            stream_timeout ->
              raise "Timeout waiting for next chunk in stream"
          end
      end,
      fn _ -> nil end
    )
    |> SSEStreamParser.parse()
    |> Utils.guard_repetitive_chunks()
    |> Stream.map(fn chunk ->
      parse_stream_chunk_for_mode(mode, chunk)
    end)
  end

  defp do_chat_completion(mode, params, config, timeout) do
    options = Keyword.merge(http_options(config, timeout), [auth_header(config), json: params])

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
       do: JSON.decode(args)

  defp parse_response_for_mode(:md_json, %{"choices" => [%{"message" => %{"content" => content}}]}),
       do: JSON.decode(content)

  defp parse_response_for_mode(:json, %{"choices" => [%{"message" => %{"content" => content}}]}),
    do: JSON.decode(content)

  defp parse_response_for_mode(:json_schema, %{
         "choices" => [%{"message" => %{"content" => content}}]
       }),
       do: JSON.decode(content)

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

  defp http_options(_config, timeout) do
    [receive_timeout: timeout, retry: :transient, max_retries: 1]
  end

  defp config(nil), do: config(Application.get_env(:instructor, :openai, []))

  defp config(base_config) do
    default_config =
      Keyword.merge(
        [
          api_url: "https://api.openai.com",
          api_path: "/v1/chat/completions",
          api_key: System.get_env("OPENAI_API_KEY"),
          auth_mode: :bearer
        ],
        Application.get_env(:instructor, :openai, [])
      )

    Keyword.merge(default_config, base_config)
  end
end
