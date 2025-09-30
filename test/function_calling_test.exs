defmodule FunctionCallingTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  setup do
    Application.put_env(:instructor, :adapter, FunctionCallingTest.MockOpenAI)
    :ok
  end

  describe "function calling with json_schema mode" do
    test "executes function and returns structured response" do
      # Create a test function
      get_weather = Instructor.Function.new!(%{
        name: "get_weather",
        description: "Get the current weather in a given location",
        parameters_schema: %{
          type: "object",
          properties: %{
            location: %{
              type: "string",
              description: "The city and state, e.g. San Francisco, CA"
            }
          },
          required: ["location"]
        },
        function: fn %{"location" => location} ->
          {:ok, %{temperature: 72, condition: "sunny", location: location}}
        end
      })

      # Mock the first response - LLM decides to call the function
      FunctionCallingTest.MockOpenAI
      |> expect(:chat_completion, fn params, _config ->
        # Verify the tools were properly formatted
        assert [%{type: "function", function: tool}] = params[:tools]
        assert tool["name"] == "get_weather"
        assert tool["description"] == "Get the current weather in a given location"

        # Return a tool call response
        {:ok,
         %{
           "id" => "chatcmpl-123",
           "choices" => [
             %{
               "finish_reason" => "tool_calls",
               "index" => 0,
               "message" => %{
                 "role" => "assistant",
                 "content" => nil,
                 "tool_calls" => [
                   %{
                     "id" => "call_abc123",
                     "type" => "function",
                     "function" => %{
                       "name" => "get_weather",
                       "arguments" => ~s({"location": "San Francisco, CA"})
                     }
                   }
                 ]
               }
             }
           ],
           "model" => "gpt-4o-mini",
           "object" => "chat.completion"
         }, nil}
      end)

      # Mock the second response - LLM uses tool result to generate final answer
      |> expect(:chat_completion, fn params, _config ->
        # params will be a Map after being processed by the adapter
        # Verify the tool result was added to messages
        messages = params[:messages] || params.messages
        assert length(messages) == 3  # original + assistant with tool_call + tool result
        
        # Check that tools have been removed for the final call
        if is_map(params) do
          refute Map.has_key?(params, :tools)
          # Verify response_format is set for structured output
          assert params.response_format.type == "json_schema"
        else
          refute Keyword.has_key?(params, :tools)
          # Verify response_format is set for structured output
          assert params[:response_format][:type] == "json_schema"
        end

        # Return final structured response
        {:ok,
         %{
           "id" => "chatcmpl-456",
           "choices" => [
             %{
               "finish_reason" => "stop",
               "index" => 0,
               "message" => %{
                 "role" => "assistant",
                 "content" => ~s({"answer": "The current weather in San Francisco, CA is sunny with a temperature of 72°F."})
               }
             }
           ],
           "model" => "gpt-4o-mini",
           "object" => "chat.completion"
         }, %{"answer" => "The current weather in San Francisco, CA is sunny with a temperature of 72°F."}}
      end)

      # Call chat_completion with function
      result = Instructor.chat_completion(
        model: "gpt-4o-mini",
        mode: :json_schema,
        functions: [get_weather],
        response_model: %{answer: :string},
        messages: [
          %{role: "user", content: "What's the weather in San Francisco?"}
        ]
      )

      assert {:ok, %{answer: answer}} = result
      assert answer =~ "San Francisco"
      assert answer =~ "72"
      assert answer =~ "sunny"
    end

    test "handles function execution errors gracefully" do
      # Create a function that returns an error
      failing_function = Instructor.Function.new!(%{
        name: "failing_function",
        description: "A function that fails",
        parameters_schema: %{
          type: "object",
          properties: %{
            input: %{type: "string"}
          },
          required: ["input"]
        },
        function: fn _args ->
          {:error, "Something went wrong"}
        end
      })

      # Mock the first response - LLM calls the function
      FunctionCallingTest.MockOpenAI
      |> expect(:chat_completion, fn _params, _config ->
        {:ok,
         %{
           "id" => "chatcmpl-123",
           "choices" => [
             %{
               "message" => %{
                 "role" => "assistant",
                 "tool_calls" => [
                   %{
                     "id" => "call_123",
                     "type" => "function",
                     "function" => %{
                       "name" => "failing_function",
                       "arguments" => ~s({"input": "test"})
                     }
                   }
                 ]
               }
             }
           ]
         }, nil}
      end)

      # Mock the second response - LLM handles the error
      |> expect(:chat_completion, fn params, _config ->
        # Check that the error was passed to the LLM
        tool_message = Enum.find(params[:messages], &(&1["role"] == "tool"))
        assert tool_message["content"] =~ "Something went wrong"

        {:ok,
         %{
           "id" => "chatcmpl-456",
           "choices" => [
             %{
               "message" => %{
                 "role" => "assistant",
                 "content" => ~s({"error": "The function failed with error: Something went wrong"})
               }
             }
           ]
         }, %{"error" => "The function failed with error: Something went wrong"}}
      end)

      result = Instructor.chat_completion(
        model: "gpt-4o-mini",
        mode: :json_schema,
        functions: [failing_function],
        response_model: %{error: :string},
        messages: [
          %{role: "user", content: "Test the function"}
        ]
      )

      assert {:ok, %{error: error_msg}} = result
      assert error_msg =~ "Something went wrong"
    end

    test "handles multiple function calls" do
      # Create two test functions
      get_time = Instructor.Function.new!(%{
        name: "get_time",
        description: "Get the current time",
        parameters_schema: %{
          type: "object",
          properties: %{},
          required: []
        },
        function: fn _args ->
          {:ok, %{time: "2:30 PM"}}
        end
      })

      get_date = Instructor.Function.new!(%{
        name: "get_date",
        description: "Get the current date",
        parameters_schema: %{
          type: "object",
          properties: %{},
          required: []
        },
        function: fn _args ->
          {:ok, %{date: "2024-01-15"}}
        end
      })

      # Mock response with multiple tool calls
      FunctionCallingTest.MockOpenAI
      |> expect(:chat_completion, fn _params, _config ->
        {:ok,
         %{
           "id" => "chatcmpl-123",
           "choices" => [
             %{
               "message" => %{
                 "role" => "assistant",
                 "tool_calls" => [
                   %{
                     "id" => "call_1",
                     "type" => "function",
                     "function" => %{
                       "name" => "get_time",
                       "arguments" => "{}"
                     }
                   },
                   %{
                     "id" => "call_2",
                     "type" => "function",
                     "function" => %{
                       "name" => "get_date",
                       "arguments" => "{}"
                     }
                   }
                 ]
               }
             }
           ]
         }, nil}
      end)

      # Mock final response
      |> expect(:chat_completion, fn params, _config ->
        # Check that both tool results were added
        tool_messages = Enum.filter(params[:messages], &(&1["role"] == "tool"))
        assert length(tool_messages) == 2

        {:ok,
         %{
           "id" => "chatcmpl-456",
           "choices" => [
             %{
               "message" => %{
                 "role" => "assistant",
                 "content" => ~s({"answer": "The current date is 2024-01-15 and the time is 2:30 PM"})
               }
             }
           ]
         }, %{"answer" => "The current date is 2024-01-15 and the time is 2:30 PM"}}
      end)

      result = Instructor.chat_completion(
        model: "gpt-4o-mini",
        mode: :json_schema,
        functions: [get_time, get_date],
        response_model: %{answer: :string},
        messages: [
          %{role: "user", content: "What's the current date and time?"}
        ]
      )

      assert {:ok, %{answer: answer}} = result
      assert answer =~ "2024-01-15"
      assert answer =~ "2:30 PM"
    end
  end
end

# Define the mock adapter for testing
Mox.defmock(FunctionCallingTest.MockOpenAI, for: Instructor.Adapter)