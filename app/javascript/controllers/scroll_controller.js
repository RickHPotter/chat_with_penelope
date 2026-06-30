import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 0 } }

  connect() {
    this.observer = new MutationObserver(() => this.scrollBottom())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.scrollBottom()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollBottom() {
    setTimeout(() => {
      this.element.scrollTop = this.element.scrollHeight
    }, this.delayValue)
  }
}
