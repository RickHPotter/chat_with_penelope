import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-white", "text-slate-950"]
const INACTIVE_CLASSES = ["text-slate-300", "hover:text-white"]

export default class extends Controller {
  static targets = ["content", "debugPayload", "defaultPanel", "targetPanel", "defaultTab", "targetTab"]
  static values = { language: { type: String, default: "target" } }

  connect() {
    this.render()
  }

  showDefault(event) {
    event.preventDefault()
    this.languageValue = "default"
    this.render()
  }

  showTarget(event) {
    event.preventDefault()
    this.languageValue = "target"
    this.render()
  }

  async copy(event) {
    event.preventDefault()

    const text = this.copySource().textContent.trim()

    await this.writeClipboard(text)
  }

  async copyDebug(event) {
    event.preventDefault()

    if (!this.hasDebugPayloadTarget) return

    await this.writeClipboard(this.debugPayloadTarget.textContent.trim())
  }

  useIntent(event) {
    event.preventDefault()

    const intent = event.currentTarget.dataset.intent
    const input = document.getElementById("message_content")
    if (!intent || !input) return

    const command = `/${intent}`
    const current = input.value.trimStart()
    const withoutCommand = current.replace(/^\/[a-zA-Z][\w-]*(\s+)?/, "")

    input.value = withoutCommand.length > 0 ? `${command} ${withoutCommand}` : `${command} `
    input.focus()
    input.selectionStart = input.value.length
    input.selectionEnd = input.value.length
  }

  render() {
    if (!this.hasDefaultPanelTarget || !this.hasTargetPanelTarget) return

    const showDefault = this.languageValue === "default"
    this.defaultPanelTarget.hidden = !showDefault
    this.targetPanelTarget.hidden = showDefault

    if (this.hasDefaultTabTarget) this.applyTabState(this.defaultTabTarget, showDefault)
    if (this.hasTargetTabTarget) this.applyTabState(this.targetTabTarget, !showDefault)
  }

  applyTabState(tab, active) {
    tab.classList.remove(...ACTIVE_CLASSES, ...INACTIVE_CLASSES)
    tab.classList.add(...(active ? ACTIVE_CLASSES : INACTIVE_CLASSES))
  }

  copySource() {
    if (this.hasDefaultPanelTarget && this.hasTargetPanelTarget) {
      return this.languageValue === "default" ? this.defaultPanelTarget : this.targetPanelTarget
    }

    return this.hasContentTarget ? this.contentTarget : this.element
  }

  async writeClipboard(text) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
    }
  }
}
