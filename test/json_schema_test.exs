Code.compiler_options(ignore_module_conflict: true, docs: true, debug_info: true)

defmodule JSONSchemaTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Instructor.JSONSchema

  test "schema" do
    defmodule Demo do
      use Ecto.Schema
      use Instructor

      @primary_key false
      schema "demo" do
        field(:string, :string)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(JSONSchemaTest.Demo)
      |> JSON.decode!()

    expected_json_schema =
      %{
        "description" => "",
        "properties" => %{
          "string" => %{
            "type" => "string",
            "description" => "String, e.g. 'hello'"
          }
        },
        "required" => ["string"],
        "title" => "JSONSchemaTest.Demo",
        "type" => "object",
        "additionalProperties" => false
      }

    assert json_schema == expected_json_schema
  end

  test "embedded_schema" do
    defmodule Demo do
      use Ecto.Schema
      use Instructor
      @primary_key false
      embedded_schema do
        field(:string, :string)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> JSON.decode!()

    expected_json_schema = %{
      "description" => "",
      "properties" => %{
        "string" => %{
          "type" => "string",
          "description" => "String, e.g. 'hello'"
        }
      },
      "required" => ["string"],
      "title" => "JSONSchemaTest.Demo",
      "type" => "object",
      "additionalProperties" => false
    }

    assert json_schema == expected_json_schema
  end

  test "includes documentation" do
    json_schema =
      JSONSchema.from_ecto_schema(InstructorTest.DemoWithUseInstructorAndNewDoc)
      |> JSON.decode!()

    expected_json_schema =
      %{
        "description" => "Hello world",
        "properties" => %{
          "string" => %{
            "type" => "string",
            "description" => "String, e.g. 'hello'"
          }
        },
        "required" => ["string"],
        "title" => "InstructorTest.DemoWithUseInstructorAndNewDoc",
        "type" => "object",
        "additionalProperties" => false
      }

    assert json_schema == expected_json_schema
  end

  test "issues deprecation warning for schema without use Instructor" do
    log =
      capture_log(fn ->
        JSONSchema.from_ecto_schema(InstructorTest.DemoRawEctoSchema)
      end)
      |> String.downcase()
      |> String.trim()

    assert log =~ String.downcase("using Ecto Schemas without `use Instructor` is deprecated")
  end

  test "issues deprecation warning for schema with @doc but no @llm_doc" do
    log =
      capture_log(fn ->
        JSONSchema.from_ecto_schema(InstructorTest.DemoWithUseInstructorButOldDoc)
      end)
      |> String.downcase()
      |> String.trim()

    assert log =~ String.downcase("using Ecto Schemas with the `@doc` attribute is deprecated")
  end

  test "include new documentation using @llm_doc" do
    defmodule Demo do
      use Instructor
      use Ecto.Schema

      @llm_doc "Hello world"
      @primary_key false
      embedded_schema do
        field(:string, :string)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> JSON.decode!()

    assert json_schema["description"] == "Hello world"
  end

  test "basic types" do
    defmodule Demo do
      use Ecto.Schema
      use Instructor
      # Be explicit about all fields in this test
      @primary_key false
      embedded_schema do
        # field(:binary_id, :binary_id)
        field(:integer, :integer)
        field(:float, :float)
        field(:boolean, :boolean)
        field(:string, :string)
        # field(:binary, :binary)
        field(:array, {:array, :string})
        field(:map, :map)
        field(:map_two, {:map, :string})
        field(:decimal, :decimal)
        field(:date, :date)
        field(:time, :time)
        field(:time_usec, :time_usec)
        field(:naive_datetime, :naive_datetime)
        field(:naive_datetime_usec, :naive_datetime_usec)
        field(:utc_datetime, :utc_datetime)
        field(:utc_datetime_usec, :utc_datetime_usec)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> JSON.decode!()

    expected_json_schema = %{
      "description" => "",
      "properties" => %{
        "array" => %{
          "items" => %{
            "description" => "String, e.g. 'hello'",
            "type" => "string"
          },
          "type" => "array"
        },
        "boolean" => %{
          "type" => "boolean",
          "description" => "Boolean, e.g. true"
        },
        "date" => %{
          "format" => "date",
          "type" => "string",
          "description" => "ISO8601 Date, e.g. \"2024-07-20\""
        },
        "decimal" => %{
          "format" => "float",
          "type" => "number"
        },
        "float" => %{
          "format" => "float",
          "type" => "number",
          "description" => "Float, e.g. 1.27"
        },
        "integer" => %{
          "type" => "integer",
          "description" => "Integer, e.g. 1"
        },
        "map" => %{
          "additionalProperties" => false,
          "type" => "object",
          "description" => "An object with arbitrary keys and values, e.g. { key: value }",
          "properties" => %{}
        },
        "map_two" => %{
          "additionalProperties" => %{
            "type" => "string",
            "description" => "String, e.g. 'hello'"
          },
          "type" => "object",
          "description" => "An object with values of a type :string, e.g. { key: value }",
          "properties" => %{}
        },
        "naive_datetime" => %{
          "format" => "date-time",
          "type" => "string",
          "description" => "ISO8601 DateTime, e.g. \"2024-07-20T12:00:00\""
        },
        "naive_datetime_usec" => %{
          "format" => "date-time",
          "description" =>
            "ISO8601 DateTime with microseconds, e.g. \"2024-07-20T12:00:00.000000\"",
          "type" => "string"
        },
        "string" => %{
          "description" => "String, e.g. 'hello'",
          "type" => "string"
        },
        "time" => %{
          "pattern" => "^[0-9]{2}:?[0-9]{2}:?[0-9]{2}$",
          "type" => "string",
          "description" => "ISO8601 Time, e.g. \"12:00:00\""
        },
        "time_usec" => %{
          "pattern" => "^[0-9]{2}:?[0-9]{2}:?[0-9]{2}.[0-9]{6}$",
          "type" => "string",
          "description" => "ISO8601 Time with microseconds, e.g. \"12:00:00.000000\""
        },
        "utc_datetime" => %{
          "format" => "date-time",
          "type" => "string",
          "description" => "ISO8601 DateTime, e.g. \"2024-07-20T12:00:00Z\""
        },
        "utc_datetime_usec" => %{
          "format" => "date-time",
          "type" => "string",
          "description" =>
            "ISO8601 DateTime with microseconds, e.g. \"2024-07-20T12:00:00.000000Z\""
        }
      },
      "required" => [
        "array",
        "boolean",
        "date",
        "decimal",
        "float",
        "integer",
        "map",
        "map_two",
        "naive_datetime",
        "naive_datetime_usec",
        "string",
        "time",
        "time_usec",
        "utc_datetime",
        "utc_datetime_usec"
      ],
      "title" => "JSONSchemaTest.Demo",
      "type" => "object",
      "additionalProperties" => false
    }

    assert json_schema == expected_json_schema
  end

  test "embedded schemas" do
    defmodule Embedded do
      use Ecto.Schema
      use Instructor
      @primary_key false
      embedded_schema do
        field(:string, :string)
      end
    end

    defmodule Demo do
      use Ecto.Schema
      use Instructor
      @primary_key false
      embedded_schema do
        embeds_one(:embedded, Embedded)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> JSON.decode!()

    expected_json_schema = %{
      "$defs" => %{
        "JSONSchemaTest.Embedded" => %{
          "description" => "",
          "properties" => %{
            "string" => %{
              "type" => "string",
              "description" => "String, e.g. 'hello'"
            }
          },
          "required" => ["string"],
          "title" => "JSONSchemaTest.Embedded",
          "type" => "object",
          "additionalProperties" => false
        }
      },
      "description" => "",
      "properties" => %{
        "embedded" => %{
          "$ref" => "#/$defs/JSONSchemaTest.Embedded"
        }
      },
      "required" => ["embedded"],
      "title" => "JSONSchemaTest.Demo",
      "type" => "object",
      "additionalProperties" => false
    }

    assert json_schema == expected_json_schema
  end

  test "has_one" do
    defmodule Child do
      use Ecto.Schema
      use Instructor

      schema "child" do
        field(:string, :string)
      end
    end

    defmodule Demo do
      use Ecto.Schema
      use Instructor

      schema "demo" do
        has_one(:child, Child)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> JSON.decode!()

    expected_json_schema =
      %{
        "$defs" => %{
          "JSONSchemaTest.Child" => %{
            "description" => "",
            "properties" => %{
              "id" => %{
                "type" => "integer",
                "description" => "Integer, e.g. 1"
              },
              "string" => %{
                "type" => "string",
                "description" => "String, e.g. 'hello'"
              }
            },
            "required" => ["id", "string"],
            "title" => "JSONSchemaTest.Child",
            "type" => "object",
            "additionalProperties" => false
          }
        },
        "description" => "",
        "properties" => %{
          "child" => %{"$ref" => "#/$defs/JSONSchemaTest.Child"},
          "id" => %{
            "type" => "integer",
            "description" => "Integer, e.g. 1"
          }
        },
        "required" => ["child", "id"],
        "title" => "JSONSchemaTest.Demo",
        "type" => "object",
        "additionalProperties" => false
      }

    assert json_schema == expected_json_schema
  end

  test "has_many" do
    defmodule Child do
      use Ecto.Schema
      use Instructor

      schema "child" do
        field(:string, :string)
      end
    end

    defmodule Demo do
      use Ecto.Schema
      use Instructor

      schema "demo" do
        has_many(:children, Child)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> JSON.decode!()

    expected_json_schema = %{
      "$defs" => %{
        "JSONSchemaTest.Child" => %{
          "description" => "",
          "properties" => %{
            "id" => %{
              "type" => "integer",
              "description" => "Integer, e.g. 1"
            },
            "string" => %{
              "type" => "string",
              "description" => "String, e.g. 'hello'"
            }
          },
          "required" => ["id", "string"],
          "title" => "JSONSchemaTest.Child",
          "type" => "object",
          "additionalProperties" => false
        }
      },
      "description" => "",
      "properties" => %{
        "children" => %{
          "items" => %{"$ref" => "#/$defs/JSONSchemaTest.Child"},
          "title" => "JSONSchemaTest.Child",
          "type" => "array"
        },
        "id" => %{
          "type" => "integer",
          "description" => "Integer, e.g. 1"
        }
      },
      "required" => ["children", "id"],
      "title" => "JSONSchemaTest.Demo",
      "type" => "object",
      "additionalProperties" => false
    }

    assert json_schema == expected_json_schema
  end

  test "handles ecto types with embeds recursively" do
    schema = %{
      value:
        Ecto.ParameterizedType.init(Ecto.Embedded,
          cardinality: :one,
          related: %{
            name: :string,
            children:
              Ecto.ParameterizedType.init(Ecto.Embedded,
                cardinality: :many,
                related: %{name: :string}
              )
          }
        )
    }

    json_schema =
      JSONSchema.from_ecto_schema(schema)
      |> JSON.decode!()

    expected_json_schema = %{
      "properties" => %{
        "value" => %{
          "properties" => %{
            "children" => %{
              "items" => %{
                "properties" => %{
                  "name" => %{
                    "type" => "string",
                    "description" => "String, e.g. 'hello'"
                  }
                },
                "required" => ["name"],
                "type" => "object"
              },
              "type" => "array"
            },
            "name" => %{
              "type" => "string",
              "description" => "String, e.g. 'hello'"
            }
          },
          "required" => ["children", "name"],
          "type" => "object",
          "additionalProperties" => false
        }
      },
      "required" => ["value"],
      "title" => "root",
      "type" => "object",
      "additionalProperties" => false
    }

    assert json_schema == expected_json_schema
  end
end
