defmodule Instructor.Function do
  @moduledoc """
  Defines a function that can be called by the LLM.
  
  ## Example
  
      custom_fn = Instructor.Function.new!(%{
        name: "get_weather",
        description: "Get the weather for a location",
        parameters_schema: %{
          type: "object",
          properties: %{
            location: %{type: "string", description: "The city and state"}
          },
          required: ["location"]
        },
        function: fn %{"location" => location} ->
          # Your function logic here
          {:ok, %{temperature: 72, conditions: "sunny"}}
        end
      })
  """
  
  defstruct [:name, :description, :parameters_schema, :function]
  
  @doc """
  Creates a new Function struct.
  """
  def new!(params) do
    struct!(__MODULE__, params)
  end
  
  @doc """
  Executes the function with the given arguments.
  Returns {:ok, result} or {:error, reason}.
  """
  def execute(%__MODULE__{function: fun}, args) when is_function(fun) do
    case fun.(args) do
      {:ok, _} = result -> result
      {:error, _} = error -> error
      result -> {:ok, result}  # Wrap bare returns in :ok tuple
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
  
  @doc """
  Converts the function to OpenAI tool format.
  """
  def to_tool(%__MODULE__{} = func) do
    %{
      type: "function",
      function: %{
        "name" => func.name,
        "description" => func.description,
        "parameters" => func.parameters_schema
      }
    }
  end
end