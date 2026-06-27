import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-white", "text-slate-950"]
const INACTIVE_CLASSES = ["text-slate-300", "hover:text-white"]

export default class extends Controller {
  static targets = ["defaultPanel", "targetPanel", "defaultTab", "targetTab"]
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

    const activePanel = this.languageValue === "default" ? this.defaultPanelTarget : this.targetPanelTarget
    const text = activePanel.textContent.trim()

    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
    }
  }

  render() {
    const showDefault = this.languageValue === "default"
    this.defaultPanelTarget.hidden = !showDefault
    this.targetPanelTarget.hidden = showDefault

    this.applyTabState(this.defaultTabTarget, showDefault)
    this.applyTabState(this.targetTabTarget, !showDefault)
  }

  applyTabState(tab, active) {
    tab.classList.remove(...ACTIVE_CLASSES, ...INACTIVE_CLASSES)
    tab.classList.add(...(active ? ACTIVE_CLASSES : INACTIVE_CLASSES))
  }
}
