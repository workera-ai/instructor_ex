defmodule Instructor.TestHelpers do
  import Mox

  def mock_openai_response(:tools, result) do
    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      {:ok,
       %{
         "id" => "chatcmpl-8e9AVo9NHfvBG5cdtAEiJMm7q4Htz",
         "usage" => %{
           "completion_tokens" => 23,
           "prompt_tokens" => 136,
           "total_tokens" => 159
         },
         "choices" => [
           %{
             "finish_reason" => "stop",
             "index" => 0,
             "logprobs" => nil,
             "message" => %{
               "content" => nil,
               "role" => "assistant",
               "tool_calls" => [
                 %{
                   "function" => %{
                     "arguments" => JSON.encode!(result),
                     "name" => "schema"
                   },
                   "id" => "call_DT9fBvVCHWGSf9IeFZnlarIY",
                   "type" => "function"
                 }
               ]
             }
           }
         ],
         "model" => "gpt-4o-mini-0613",
         "object" => "chat.completion",
         "created" => 1_704_579_055,
         "system_fingerprint" => nil
       }, result}
    end)
  end

  def mock_openai_response(mode, result) when mode in [:json, :md_json] do
    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      {
        :ok,
        %{
          "id" => "chatcmpl-8e9AVo9NHfvBG5cdtAEiJMm7q4Htz",
          "usage" => %{
            "completion_tokens" => 23,
            "prompt_tokens" => 136,
            "total_tokens" => 159
          },
          "choices" => [
            %{
              "finish_reason" => "stop",
              "index" => 0,
              "logprobs" => nil,
              "message" => %{
                "content" => JSON.encode!(result),
                "role" => "assistant"
              }
            }
          ],
          "model" => "gpt-4o-mini-0613",
          "object" => "chat.completion",
          "created" => 1_704_579_055,
          "system_fingerprint" => nil
        },
        result
      }
    end)
  end

  def mock_openai_response_stream(:tools, result) do
    chunks =
      JSON.encode!(%{value: result})
      |> String.graphemes()
      |> Enum.chunk_every(12)
      |> Enum.map(fn chunk ->
        Enum.join(chunk, "")
      end)

    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      chunks
    end)
  end

  def mock_openai_response_stream(mode, result) when mode in [:json, :md_json] do
    chunks =
      JSON.encode!(%{value: result})
      |> String.graphemes()
      |> Enum.chunk_every(12)
      |> Enum.map(fn chunk ->
        Enum.join(chunk, "")
      end)

    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      chunks
    end)
  end

  def mock_openai_reask_messages() do
    InstructorTest.MockOpenAI
    |> expect(:reask_messages, fn _raw_response, _params, _config ->
      []
    end)
  end

  def mock_openai_response_stream_with_delay(:tools, result, opts \\ []) do
    initial_delay = Keyword.get(opts, :initial_delay, 0)
    chunk_delay = Keyword.get(opts, :chunk_delay, 0)

    chunks =
      JSON.encode!(%{value: result})
      |> String.graphemes()
      |> Enum.chunk_every(12)
      |> Enum.map(fn chunk -> Enum.join(chunk, "") end)

    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      Stream.resource(
        fn ->
          # Sleep for initial delay before returning first chunk
          if initial_delay > 0, do: Process.sleep(initial_delay)
          {chunks, false}
        end,
        fn
          {[], _} ->
            {:halt, nil}

          {[chunk | rest], is_first_done} ->
            # Sleep between chunks (but not before the first one)
            if is_first_done and chunk_delay > 0 do
              Process.sleep(chunk_delay)
            end

            {[chunk], {rest, true}}
        end,
        fn _ -> nil end
      )
    end)
  end

  def mock_openai_response_with_delay(:tools, result, opts \\ []) do
    delay = Keyword.get(opts, :delay, 0)

    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      if delay > 0, do: Process.sleep(delay)

      {:ok,
       %{
         "id" => "chatcmpl-8e9AVo9NHfvBG5cdtAEiJMm7q4Htz",
         "usage" => %{
           "completion_tokens" => 23,
           "prompt_tokens" => 136,
           "total_tokens" => 159
         },
         "choices" => [
           %{
             "finish_reason" => "stop",
             "index" => 0,
             "logprobs" => nil,
             "message" => %{
               "content" => nil,
               "role" => "assistant",
               "tool_calls" => [
                 %{
                   "function" => %{
                     "arguments" => JSON.encode!(result),
                     "name" => "schema"
                   },
                   "id" => "call_DT9fBvVCHWGSf9IeFZnlarIY",
                   "type" => "function"
                 }
               ]
             }
           }
         ],
         "model" => "gpt-4o-mini-0613",
         "object" => "chat.completion",
         "created" => 1_704_579_055,
         "system_fingerprint" => nil
       }, result}
    end)
  end

  def is_stream?(variable) do
    case variable do
      %Stream{} ->
        true

      _ when is_function(variable, 0) or is_function(variable, 1) or is_function(variable, 2) ->
        true

      _ ->
        false
    end
  end
end
