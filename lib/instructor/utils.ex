defmodule Instructor.Utils do
  @moduledoc """
  Utility functions for Instructor
  """

  defmodule RepetitiveChunksError do
    defexception [:message, :content, :count]

    def exception(opts) do
      content = Keyword.fetch!(opts, :content)
      count = Keyword.fetch!(opts, :count)

      %__MODULE__{
        message:
          "Detected #{count} consecutive repetitive chunks with content: #{inspect(content)}",
        content: content,
        count: count
      }
    end
  end

  @doc """
  Guards against repetitive chunks in a stream by counting consecutive
  identical content chunks and raising an exception after a threshold.

  ## Options
    * `:max_repetitions` - Maximum consecutive identical chunks before raising (default: 30)
    * `:content_extractor` - Function to extract content from chunk (default: extracts from OpenAI format)
  """
  def guard_repetitive_chunks(stream, opts \\ []) do
    max_repetitions = Keyword.get(opts, :max_repetitions, 30)

    extractor =
      Keyword.get(opts, :content_extractor, fn
        %{"choices" => [%{"delta" => %{"content" => content}}]} -> String.trim(content)
        %{"choices" => [%{"delta" => delta}]} when is_map(delta) -> ""
        _ -> ""
      end)

    Stream.transform(
      stream,
      # initial accumulator: {last_content, count}
      fn -> {nil, 0} end,
      fn chunk, {last_content, count} ->
        content = extractor.(chunk)

        if content == last_content do
          new_count = count + 1

          if new_count > max_repetitions do
            raise RepetitiveChunksError, content: content, count: new_count
          else
            {[chunk], {content, new_count}}
          end
        else
          # new content, reset count to 1
          {[chunk], {content, 1}}
        end
      end,
      fn _ -> nil end
    )
  end
end
