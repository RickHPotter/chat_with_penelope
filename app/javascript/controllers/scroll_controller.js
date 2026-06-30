import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 0 } }

  connect() {
    this.observer = new MutationObserver(() => this.scrollBottom())
    this.observer.observe(this.element, {
      childList: true,
      subtree: true,
      characterData: true
    })
    this.scrollBottom()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollBottom() {
    setTimeout(() => this.forceBottom(), this.delayValue)
    requestAnimationFrame(() => this.forceBottom())
    requestAnimationFrame(() => requestAnimationFrame(() => this.forceBottom()))
  }

  forceBottom() {
    this.element.scrollTop = this.element.scrollHeight
    document.documentElement.scrollTop = document.documentElement.scrollHeight
    document.body.scrollTop = document.body.scrollHeight
  }
}
