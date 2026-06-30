import { Controller } from "@hotwired/stimulus"

const MAX_OPTIONS = 4
const COMMAND_PATTERN = /^\/([a-z_]*)$/i

export default class extends Controller {
  static targets = ["input", "menu", "options"]
  static values = { actions: Array }

  connect() {
    this.activeIndex = 0
    this.filteredActions = []
    this.hide()
  }

  keydown(event) {
    if (event.key === "Enter") {
      this.handleEnter(event)
      return
    }

    if (event.key === "ArrowDown" && this.menuOpen) {
      event.preventDefault()
      this.move(1)
      return
    }

    if (event.key === "ArrowUp" && this.menuOpen) {
      event.preventDefault()
      this.move(-1)
      return
    }

    if (event.key === "Tab" && this.menuOpen) {
      event.preventDefault()
      this.completeSelected()
      return
    }

    if (event.key === "Escape" && this.menuOpen) {
      event.preventDefault()
      this.hide()
    }
  }

  input() {
    this.render()
  }

  blur() {
    setTimeout(() => this.hide(), 120)
  }

  choose(event) {
    event.preventDefault()

    const index = Number(event.currentTarget.dataset.index)
    if (!Number.isNaN(index)) this.activeIndex = index

    this.completeSelected()
  }

  handleEnter(event) {
    if (this.menuOpen) {
      event.preventDefault()
      this.completeSelected()
      return
    }

    if (event.shiftKey || event.ctrlKey) return

    event.preventDefault()
    this.hide()
    this.element.requestSubmit()
  }

  render() {
    const query = this.commandQuery()

    if (query === null) {
      this.hide()
      return
    }

    this.filteredActions = this.actionsValue
      .filter((action) => action.command.startsWith(query))
      .slice(0, MAX_OPTIONS)

    if (this.filteredActions.length === 0) {
      this.hide()
      return
    }

    this.activeIndex = Math.min(this.activeIndex, this.filteredActions.length - 1)
    this.optionsTarget.replaceChildren(...this.filteredActions.map((action, index) => this.optionElement(action, index)))
    this.show()
  }

  move(step) {
    this.activeIndex = (this.activeIndex + step + this.filteredActions.length) % this.filteredActions.length
    this.render()
  }

  completeSelected() {
    const action = this.filteredActions[this.activeIndex]
    if (!action) return

    const value = this.inputTarget.value
    const caret = this.inputTarget.selectionStart
    const suffix = value.slice(caret)
    const before = value.slice(0, caret)
    const commandStart = before.lastIndexOf("/")
    const replacement = `/${action.command} `
    const nextValue = `${before.slice(0, commandStart)}${replacement}${suffix.replace(/^\s+/, "")}`
    const nextCaret = commandStart + replacement.length

    this.inputTarget.value = nextValue
    this.inputTarget.focus()
    this.inputTarget.setSelectionRange(nextCaret, nextCaret)
    this.hide()
  }

  commandQuery() {
    const input = this.inputTarget
    const caret = input.selectionStart
    const before = input.value.slice(0, caret)

    if (input.selectionStart !== input.selectionEnd) return null
    if (before.includes("\n")) return null
    if (!before.startsWith("/")) return null
    if (before.includes(" ")) return null

    const match = before.match(COMMAND_PATTERN)
    return match ? match[1].toLowerCase() : null
  }

  optionElement(action, index) {
    const selected = index === this.activeIndex
    const button = document.createElement("button")
    button.type = "button"
    button.dataset.action = "mousedown->composer#choose mouseenter->composer#hover"
    button.dataset.index = String(index)
    button.className = [
      "group",
      "flex",
      "w-full",
      "items-center",
      "gap-3",
      "rounded-2xl",
      "px-3",
      "py-3",
      "text-left",
      "transition",
      selected ? "bg-sky-300 text-slate-950 shadow-lg shadow-sky-950/30" : "text-slate-200 hover:bg-white/10"
    ].join(" ")

    button.innerHTML = `
      <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl ${selected ? "bg-slate-950 text-sky-200" : "bg-sky-300/10 text-sky-200"} font-semibold">/${action.command.charAt(0)}</span>
      <span class="min-w-0 flex-1">
        <span class="flex items-center gap-2">
          <span class="font-semibold">/${action.command}</span>
          <span class="${selected ? "text-slate-700" : "text-slate-500"} text-xs">${action.intent}</span>
        </span>
        <span class="${selected ? "text-slate-800" : "text-slate-400"} mt-0.5 block truncate text-sm">${action.hint}</span>
      </span>
      <span class="${selected ? "border-slate-800/20 text-slate-800" : "border-white/10 text-slate-500"} rounded-full border px-2 py-1 text-[0.65rem] uppercase tracking-[0.18em]">Tab</span>
    `

    return button
  }

  hover(event) {
    const index = Number(event.currentTarget.dataset.index)
    if (Number.isNaN(index)) return

    this.activeIndex = index
    this.render()
  }

  show() {
    this.menuTarget.classList.remove("hidden")
    this.menuOpen = true
  }

  hide() {
    this.menuTarget.classList.add("hidden")
    this.menuOpen = false
  }
}
