import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field"]

  pick(event) {
    this.fieldTarget.value = event.currentTarget.dataset.location
  }
}
