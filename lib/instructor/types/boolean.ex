defmodule Instructor.Types.Boolean do
  @moduledoc """
  A custom Ecto type for boolean with extended JSON Schema attributes.

  This type extends the basic Ecto boolean type with additional JSON Schema properties
  like description.

  ## Example
      schema "users" do
        field :is_admin, Instructor.Types.Boolean,
          description: "Whether the user is an administrator"
      end
  """
  use Ecto.ParameterizedType
  use Instructor.EctoType

  # Initialize the type with the given parameters
  def init(opts), do: Enum.into(opts, %{})

  # The underlying Ecto type
  def type(_opts), do: :boolean

  # Cast with options
  def cast(nil, _opts), do: {:ok, nil}

  def cast(value, _opts) when is_boolean(value), do: {:ok, value}

  def cast(_value, _opts), do: :error

  # Load with options
  def load(_opts, nil), do: {:ok, nil}
  def load(_opts, value) when is_boolean(value), do: {:ok, value}
  def load(_opts, _), do: :error

  # Dump with options (2-arity version for compatibility)
  def dump(_opts, nil), do: {:ok, nil}
  def dump(_opts, value) when is_boolean(value), do: {:ok, value}
  def dump(_opts, _), do: :error

  # Dump with options and dumper function (3-arity version for ParameterizedType)
  def dump(nil, _dumper, _opts), do: {:ok, nil}
  def dump(value, _dumper, _opts) when is_boolean(value), do: {:ok, value}
  def dump(_, _, _), do: :error

  # Load with options and loader function (3-arity version for ParameterizedType)
  def load(nil, _loader, _opts), do: {:ok, nil}
  def load(value, _loader, _opts) when is_boolean(value), do: {:ok, value}
  def load(_, _, _), do: :error

  # These are required by Ecto.ParameterizedType
  def embed_as(_opts, _format), do: :self

  def equal?(_opts, a, b), do: a == b

  # JSON Schema generation
  def to_json_schema(opts, context \\ %{}) do
    %{"type" => "boolean"}
    |> maybe_add("description", opts[:description], context)
  end

  defp maybe_add(map, _key, nil, _context), do: map

  defp maybe_add(map, key, value, context) when is_function(value, 1),
    do: Map.put(map, key, value.(context))

  defp maybe_add(map, key, value, _context), do: Map.put(map, key, value)
end
