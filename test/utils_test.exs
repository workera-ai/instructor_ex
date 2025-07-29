defmodule Instructor.UtilsTest do
  use ExUnit.Case

  alias Instructor.Utils
  alias Instructor.Utils.RepetitiveChunksError

  describe "guard_repetitive_chunks/2" do
    test "allows normal varied content through" do
      chunks = [
        %{"choices" => [%{"delta" => %{"content" => "Hello"}}]},
        %{"choices" => [%{"delta" => %{"content" => " world"}}]},
        %{"choices" => [%{"delta" => %{"content" => "!"}}]},
        %{"choices" => [%{"delta" => %{"content" => "\n"}}]},
        %{"choices" => [%{"delta" => %{"content" => "How"}}]},
        %{"choices" => [%{"delta" => %{"content" => " are"}}]},
        %{"choices" => [%{"delta" => %{"content" => " you?"}}]}
      ]

      result =
        chunks
        |> Utils.guard_repetitive_chunks()
        |> Enum.to_list()

      assert result == chunks
    end

    test "raises on repetitive newlines exceeding threshold" do
      newline_chunk = %{"choices" => [%{"delta" => %{"content" => "\n"}}]}
      chunks = List.duplicate(newline_chunk, 35)

      assert_raise RepetitiveChunksError,
                   ~r/Detected 31 consecutive repetitive chunks with content: ""/,
                   fn ->
                     chunks
                     |> Utils.guard_repetitive_chunks()
                     |> Enum.to_list()
                   end
    end

    test "raises on repetitive non-empty content" do
      dot_chunk = %{"choices" => [%{"delta" => %{"content" => "..."}}]}
      chunks = List.duplicate(dot_chunk, 32)

      assert_raise RepetitiveChunksError,
                   ~r/Detected 31 consecutive repetitive chunks with content: "..."/,
                   fn ->
                     chunks
                     |> Utils.guard_repetitive_chunks()
                     |> Enum.to_list()
                   end
    end

    test "resets counter when content changes" do
      chunks =
        List.duplicate(%{"choices" => [%{"delta" => %{"content" => "\n"}}]}, 20) ++
          [%{"choices" => [%{"delta" => %{"content" => "Hello"}}]}] ++
          List.duplicate(%{"choices" => [%{"delta" => %{"content" => "\n"}}]}, 20)

      result =
        chunks
        |> Utils.guard_repetitive_chunks()
        |> Enum.to_list()

      assert length(result) == 41
    end

    test "respects custom max_repetitions option" do
      chunk = %{"choices" => [%{"delta" => %{"content" => "a"}}]}
      chunks = List.duplicate(chunk, 10)

      assert_raise RepetitiveChunksError,
                   ~r/Detected 6 consecutive repetitive chunks/,
                   fn ->
                     chunks
                     |> Utils.guard_repetitive_chunks(max_repetitions: 5)
                     |> Enum.to_list()
                   end
    end

    test "handles whitespace trimming correctly" do
      chunks = [
        %{"choices" => [%{"delta" => %{"content" => "  \n  "}}]},
        %{"choices" => [%{"delta" => %{"content" => "\t\n"}}]},
        %{"choices" => [%{"delta" => %{"content" => "   "}}]}
      ]

      # All should be treated as empty after trimming
      result =
        chunks
        |> Utils.guard_repetitive_chunks()
        |> Enum.to_list()

      assert length(result) == 3
    end

    test "works with custom content extractor" do
      chunks = List.duplicate(%{"data" => "xyz"}, 35)

      extractor = fn
        %{"data" => data} -> data
        _ -> ""
      end

      assert_raise RepetitiveChunksError,
                   ~r/Detected 31 consecutive repetitive chunks with content: "xyz"/,
                   fn ->
                     chunks
                     |> Utils.guard_repetitive_chunks(content_extractor: extractor)
                     |> Enum.to_list()
                   end
    end

    test "handles empty delta maps" do
      chunks = [
        %{"choices" => [%{"delta" => %{"content" => "Hello"}}]},
        %{"choices" => [%{"delta" => %{}}]},
        %{"choices" => [%{"delta" => %{}}]},
        %{"choices" => [%{"delta" => %{"content" => "World"}}]}
      ]

      result =
        chunks
        |> Utils.guard_repetitive_chunks()
        |> Enum.to_list()

      assert result == chunks
    end

    test "handles chunks without expected structure" do
      chunks = [
        %{"choices" => [%{"delta" => %{"content" => "Hello"}}]},
        %{"something" => "else"},
        %{},
        %{"choices" => [%{"delta" => %{"content" => "World"}}]}
      ]

      result =
        chunks
        |> Utils.guard_repetitive_chunks()
        |> Enum.to_list()

      assert result == chunks
    end
  end
end
