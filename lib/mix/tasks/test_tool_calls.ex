defmodule Mix.Tasks.Instructor.TestToolCalls do
  @moduledoc """
  Tests the function calling feature by calling LLM with sample functions.

  ## Usage

      mix instructor.test_tool_calls
  """
  use Mix.Task

  @shortdoc "Tests the function calling feature"
  def run(_) do
    # Ensure all dependencies are started
    Mix.Task.run("app.start")

    # Define sample functions
    get_weather =
      Instructor.Function.new!(%{
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
          # Simulate weather API call
          weather_data = %{
            location: location,
            temperature: Enum.random(60..85),
            condition: Enum.random(["sunny", "cloudy", "rainy", "partly cloudy"])
          }

          IO.puts("🌤️  Getting weather for #{location}...")
          {:ok, weather_data}
        end
      })

    get_time =
      Instructor.Function.new!(%{
        name: "get_time",
        description: "Get the current time",
        parameters_schema: %{
          type: "object",
          properties: %{},
          required: []
        },
        function: fn _args ->
          current_time = DateTime.utc_now() |> DateTime.to_string()
          IO.puts("🕐 Getting current time...")
          {:ok, %{current_time: current_time}}
        end
      })

    # Define response model for final answer
    defmodule TestResponse do
      use Ecto.Schema
      use Instructor

      @primary_key false
      embedded_schema do
        field :answer, Instructor.Types.String,
          description: "A helpful response to the user's question"
      end
    end

    IO.puts("🚀 Testing function calling with weather and time functions...")
    IO.puts("")

    result =
      Instructor.chat_completion(
        [
          model: "gpt-4o-mini",
          mode: :json_schema,
          functions: [get_weather, get_time],
          response_model: TestResponse,
          messages: [
            %{
              role: "user",
              content: "What's the weather like in New York and what time is it?"
            }
          ]
        ],
        adapter: Instructor.Adapters.OpenAI
      )

    IO.puts("")
    IO.puts("📝 Result:")
    IO.inspect(result, pretty: true)
  end
end

