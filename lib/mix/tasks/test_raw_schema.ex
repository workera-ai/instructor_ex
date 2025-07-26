defmodule Mix.Tasks.Instructor.TestRawSchema do
  @moduledoc """
  Tests the raw schema functionality by using a pre-defined JSON schema.

  ## Usage

      mix instructor.test_raw_schema
  """
  use Mix.Task

  @shortdoc "Tests the raw schema functionality"
  def run(_) do
    # Ensure all dependencies are started
    Mix.Task.run("app.start")

    # Define a raw JSON schema (similar to what would come from bfs_from_ecto_schema)
    raw_schema = %{
      "type" => "object",
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "The name of the test item",
          "minLength" => 3,
          "maxLength" => 50
        },
        "count" => %{
          "type" => "integer",
          "description" => "The count of items",
          "minimum" => 0,
          "maximum" => 100
        },
        "status" => %{
          "type" => "string",
          "enum" => ["active", "pending", "completed"],
          "description" => "The status of the item"
        },
        "is_active" => %{
          "type" => "boolean",
          "description" => "Whether the item is active"
        }
      },
      "required" => ["name", "count", "status", "is_active"],
      "additionalProperties" => false
    }

    # Pretty print the schema
    IO.puts("Using Raw JSON Schema:")
    IO.puts(Jason.encode!(raw_schema, pretty: true))

    IO.puts("\nTesting raw schema functionality...")

    case Instructor.chat_completion(
           model: "gpt-4o-mini",
           response_model: {:raw_schema, raw_schema},
           mode: :json_schema,
           messages: [
             %{
               role: "user",
               content:
                 "Generate test data for an item with name 'TestItem', count 42, status 'active', and is_active true"
             }
           ]
         ) do
      {:ok, result} ->
        IO.puts("\nSuccess! Raw schema result:")
        IO.puts(Jason.encode!(result, pretty: true))

      {:error, error} ->
        IO.puts("\nError: #{inspect(error)}")
    end
  end
end
