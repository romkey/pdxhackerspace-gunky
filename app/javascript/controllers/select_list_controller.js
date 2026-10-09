import { Controller } from "@hotwired/stimulus"

// Toggles a list between normal mode (per-item actions) and select mode
// (checkboxes plus a single bulk action button).
export default class extends Controller {
  static targets = ["checkbox", "itemAction", "selectButton", "dismissButton", "cancelButton"]

  enter() {
    this.setSelecting(true)
  }

  exit() {
    this.checkboxTargets.forEach((checkbox) => { checkbox.checked = false })
    this.setSelecting(false)
  }

  update() {
    if (this.hasDismissButtonTarget) {
      this.dismissButtonTarget.disabled = !this.checkboxTargets.some((checkbox) => checkbox.checked)
    }
  }

  setSelecting(selecting) {
    this.checkboxTargets.forEach((checkbox) => checkbox.classList.toggle("d-none", !selecting))
    this.itemActionTargets.forEach((action) => action.classList.toggle("d-none", selecting))
    if (this.hasSelectButtonTarget) this.selectButtonTarget.classList.toggle("d-none", selecting)
    if (this.hasDismissButtonTarget) this.dismissButtonTarget.classList.toggle("d-none", !selecting)
    if (this.hasCancelButtonTarget) this.cancelButtonTarget.classList.toggle("d-none", !selecting)
    this.update()
  }
}
