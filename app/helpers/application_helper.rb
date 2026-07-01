# frozen_string_literal: true

module ApplicationHelper
  def markdown_like(content)
    lines = content.to_s.lines.map(&:chomp)
    blocks = []
    list_items = []

    flush_list = lambda do
      next if list_items.empty?

      blocks << tag.ul(class: "my-3 space-y-1 pl-5 text-slate-200 marker:text-sky-300") do
        safe_join(list_items.map { |item| tag.li(inline_markdown(item), class: "list-disc leading-7") })
      end
      list_items = []
    end

    lines.each do |line|
      stripped = line.strip

      if stripped.blank?
        flush_list.call
        next
      end

      if stripped.start_with?("# ")
        flush_list.call
        blocks << tag.h3(inline_markdown(stripped.delete_prefix("# ").strip), class: "mt-4 text-sm font-semibold uppercase tracking-[0.2em] text-sky-200")
      elsif stripped.start_with?("## ")
        flush_list.call
        blocks << tag.h4(inline_markdown(stripped.delete_prefix("## ").strip), class: "mt-4 text-sm font-semibold text-sky-100")
      elsif stripped.match?(/\A[-*]\s+/)
        list_items << stripped.sub(/\A[-*]\s+/, "")
      else
        flush_list.call
        blocks << tag.p(inline_markdown(stripped), class: "my-2 leading-7")
      end
    end

    flush_list.call
    safe_join(blocks)
  end

  def message_debug_payload(message)
    JSON.pretty_generate(
      id: message.id,
      role: message.role,
      generation_status: message.generation_status,
      audio_url: message.audio_url,
      content_default_language: message.content_default_language,
      content_target_language: message.content_target_language,
      content_thinking: message.content_thinking,
      raw_response: message.raw_response,
      prompt_metadata: message.prompt_metadata
    )
  end

  private

  def inline_markdown(content)
    escaped = ERB::Util.html_escape(content.to_s)
    escaped = escaped.gsub(/`([^`]+)`/, '<code class="rounded bg-slate-950/70 px-1.5 py-0.5 text-[0.9em] text-sky-100">\1</code>')
    escaped = escaped.gsub(/\*\*([^*]+)\*\*/, '<strong class="font-semibold text-white">\1</strong>')
    escaped.html_safe
  end
end
