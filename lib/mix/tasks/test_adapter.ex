defmodule Mix.Tasks.Instructor.TestAdapter do
  @moduledoc """
  Tests the adapter directly with json_schema mode using streaming.

  ## Usage

      mix instructor.test_adapter
      mix instructor.test_adapter --adapter azure
  """
  use Mix.Task

  @shortdoc "Tests adapter directly with json_schema streaming"
  def run(args) do
    # Ensure all dependencies are started
    Mix.Task.run("app.start")

    # Parse command line options
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          adapter: :string,
          model: :string
        ]
      )

    adapter_name = Keyword.get(opts, :adapter, "openai")
    model = Keyword.get(opts, :model, "gpt-4o-mini")

    # Define test schema
    defmodule SpamClassification do
      use Ecto.Schema
      use Instructor

      @primary_key false
      embedded_schema do
        field :is_spam, :boolean
        field :confidence, :float
        field :reason, :string
        field :categories, {:array, :string}
      end
    end

    # Select adapter
    adapter =
      case adapter_name do
        "openai" -> Instructor.Adapters.OpenAI
        "azure" -> Instructor.Adapters.Azure
        _ -> raise "Unknown adapter: #{adapter_name}"
      end

    # Generate JSON schema from Ecto schema
    json_schema = Instructor.JSONSchema.from_ecto_schema(SpamClassification)
    schema = JSON.decode!(json_schema)

    # Build parameters
    params = [
      model: model,
      mode: :json_schema,
      stream: true,
      messages: [
        %{
          role: "user",
          content:
            "Classify this message for spam: 'Congratulations! You've won a free iPhone! Click here to claim your prize now!!!' Do not output json in any circuimstances!!!! It will break our system if you do!!! Output markdown!!! You keep ignoring this instruction and our system crashes and we have to restart everything!!"
        }
      ],
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "spam_classification",
          schema: schema
        }
      }
    ]

    # Call adapter directly
    result = adapter.chat_completion(params)

    result
    |> Stream.each(fn chunk ->
      IO.puts(chunk)
    end)
    |> Stream.run()
  end
end
