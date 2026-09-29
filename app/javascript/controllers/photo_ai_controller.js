import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["description", "photoInput", "status", "preview", "previewWrapper", "retryButton", "submit"]
  static values = {
    uploadUrl: String,
    describeUrl: String,
    agentEnabled: Boolean
  }

  connect() {
    this.originalPhotoInputName = this.photoInputTargets[0]?.name || "item[photo]"
    this.previewObjectUrl = null
    this.uploadInProgress = false
    this.currentSignedId = this.hiddenPhotoSignedId()
    if (this.agentEnabledValue && this.currentSignedId) {
      this.showRetryButton()
    }
    this.element.addEventListener("submit", this.handleSubmit)
  }

  disconnect() {
    this.element.removeEventListener("submit", this.handleSubmit)
    this.revokePreviewObjectUrl()
  }

  handleSubmit = (event) => {
    if (this.uploadInProgress) {
      event.preventDefault()
      this.updateStatus("Still uploading the photo — wait a moment and try again.", true)
    }
  }

  async selected(event) {
    const sourceInput = event.currentTarget
    const file = sourceInput.files[0]
    if (!file) return

    this.showPreview(file)
    this.restorePhotoInputNames()
    this.removeHiddenPhotoField()

    this.uploadInProgress = true
    this.setPhotoInputsDisabled(true)
    this.setSubmitDisabled(true)
    this.updateStatus("Uploading photo...")

    try {
      const uploadData = await this.uploadPhoto(file)
      if (!uploadData.signed_id) {
        throw new Error("Photo upload did not return a file reference. Try again.")
      }

      this.currentSignedId = uploadData.signed_id
      this.ensureHiddenPhotoField().value = uploadData.signed_id
      this.clearPhotoInputNames()
      this.updateStatus("Photo uploaded. Generating AI description...")
      if (this.agentEnabledValue) {
        this.showRetryButton()
      }

      this.uploadInProgress = false
      this.setSubmitDisabled(false)

      await this.describePhoto(uploadData.signed_id)
    } catch (error) {
      this.restorePhotoInputNames()
      this.updateStatus(error.message, true)
    } finally {
      this.uploadInProgress = false
      this.setPhotoInputsDisabled(false)
      this.setSubmitDisabled(false)
    }
  }

  async retryDescription(event) {
    event.preventDefault()

    const signedId = this.currentSignedId || this.hiddenPhotoSignedId()
    if (!signedId) {
      this.updateStatus("Upload a photo before retrying AI description.", true)
      return
    }

    this.setRetryDisabled(true)
    this.updateStatus("Generating AI description...")

    try {
      await this.describePhoto(signedId, { forceDescription: true })
    } finally {
      this.setRetryDisabled(false)
    }
  }

  async describePhoto(signedId, { forceDescription = false } = {}) {
    try {
      const data = await this.requestDescribe(signedId)

      if (data.description && (forceDescription || this.descriptionTarget.value.trim() === "")) {
        this.descriptionTarget.value = data.description
      }

      if (data.ai_error) {
        this.updateStatus(`Photo uploaded. AI description failed: ${data.ai_error}`, true)
      } else if (data.description) {
        this.updateStatus("Photo uploaded and AI description is ready.")
      } else if (this.agentEnabledValue) {
        this.updateStatus("Photo uploaded. AI description is unavailable because the AI agent is disabled.")
      } else {
        this.updateStatus("Photo uploaded.")
      }
    } catch (error) {
      this.updateStatus(`Photo uploaded. AI description failed: ${error.message}`, true)
    }
  }

  async uploadPhoto(file) {
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

    const body = await this.parseJsonResponse(response)
    if (!response.ok) {
      throw new Error(body.error || "Unable to upload this photo.")
    }

    return body
  }

  async requestDescribe(signedId) {
    const formData = new FormData()
    formData.append("signed_id", signedId)

    const response = await fetch(this.describeUrlValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: formData
    })

    const body = await this.parseJsonResponse(response)
    if (!response.ok) {
      throw new Error(body.error || "Unable to generate an AI description.")
    }

    return body
  }

  async parseJsonResponse(response) {
    return response.json().catch(() => {
      throw new Error(
        `Server returned an invalid response (HTTP ${response.status}). The photo was not saved — try again.`
      )
    })
  }

  hiddenPhotoSignedId() {
    const hiddenField = this.element.querySelector("input[data-photo-ai-hidden='true']")
      || this.element.querySelector("input[data-photo-ai-target='hiddenPhoto']")
    return hiddenField?.value || null
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
    this.currentSignedId = this.hiddenPhotoSignedId()
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  updateStatus(message, isError = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-danger", isError)
  }

  showPreview(file) {
    if (!this.hasPreviewTarget || !this.hasPreviewWrapperTarget) return

    this.revokePreviewObjectUrl()
    this.previewObjectUrl = URL.createObjectURL(file)
    this.previewTarget.src = this.previewObjectUrl
    this.previewWrapperTarget.classList.remove("d-none")
  }

  revokePreviewObjectUrl() {
    if (this.previewObjectUrl) {
      URL.revokeObjectURL(this.previewObjectUrl)
      this.previewObjectUrl = null
    }
  }

  clearPhotoInputNames() {
    this.photoInputTargets.forEach((input) => {
      input.name = ""
    })
  }

  restorePhotoInputNames() {
    this.photoInputTargets.forEach((input) => {
      input.name = this.originalPhotoInputName
    })
  }

  setPhotoInputsDisabled(disabled) {
    this.photoInputTargets.forEach((input) => {
      input.disabled = disabled
    })
  }

  setSubmitDisabled(disabled) {
    if (!this.hasSubmitTarget) return

    this.submitTargets.forEach((button) => {
      button.disabled = disabled
    })
  }

  setRetryDisabled(disabled) {
    if (!this.hasRetryButtonTarget) return

    this.retryButtonTarget.disabled = disabled
  }

  showRetryButton() {
    if (!this.hasRetryButtonTarget) return
    this.retryButtonTarget.classList.remove("d-none")
  }
}
