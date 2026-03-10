import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["description", "photoInput", "status"]
  static values = {
    uploadUrl: String
  }

  connect() {
    this.originalPhotoInputName = this.photoInputTarget.name
  }

  async selected() {
    const file = this.photoInputTarget.files[0]
    if (!file) return

    this.photoInputTarget.name = this.originalPhotoInputName
    this.removeHiddenPhotoField()

    this.photoInputTarget.disabled = true
    this.updateStatus("Uploading photo and generating AI description...")

    try {
      const data = await this.uploadAndDescribe(file)
      this.ensureHiddenPhotoField().value = data.signed_id
      this.photoInputTarget.name = ""

      if (this.descriptionTarget.value.trim() === "" && data.description) {
        this.descriptionTarget.value = data.description
      }

      if (data.description) {
        this.updateStatus("Photo uploaded and AI description is ready.")
      } else {
        this.updateStatus("Photo uploaded. AI description is unavailable because the AI agent is disabled.")
      }
    } catch (error) {
      this.photoInputTarget.name = this.originalPhotoInputName
      this.updateStatus(error.message, true)
    } finally {
      this.photoInputTarget.disabled = false
    }
  }

  async uploadAndDescribe(file) {
    const formData = new FormData()
    formData.append("photo", file)

    const response = await fetch(this.uploadUrlValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: formData
    })

    const body = await response.json()
    if (!response.ok) {
      throw new Error(body.error || "Unable to process this photo.")
    }

    return body
  }

  ensureHiddenPhotoField() {
    let hiddenField = this.element.querySelector("input[data-photo-ai-hidden='true']")

    if (!hiddenField) {
      hiddenField = document.createElement("input")
      hiddenField.type = "hidden"
      hiddenField.name = this.originalPhotoInputName
      hiddenField.dataset.photoAiHidden = "true"
      this.element.appendChild(hiddenField)
    }

    return hiddenField
  }

  removeHiddenPhotoField() {
    const hiddenField = this.element.querySelector("input[data-photo-ai-hidden='true']")
    hiddenField?.remove()
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  updateStatus(message, isError = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-danger", isError)
  }
}
