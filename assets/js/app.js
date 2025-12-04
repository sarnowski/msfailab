// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/msfailab"
import topbar from "../vendor/topbar"

// Global state for tool call box expansion (persists across LiveView updates)
const toolBoxExpandedState = new Map()

// Custom LiveView hooks
const Hooks = {
  AutoResizeTextarea: {
    mounted() {
      this.resize()
      this.el.addEventListener("input", () => this.resize())
      this.el.addEventListener("keydown", (e) => {
        // Submit form on Enter (without Shift for new lines)
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault()
          const form = this.el.closest("form")
          if (form) {
            form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
          }
        }
        // Toggle input mode on Ctrl+M
        if ((e.key === "m" || e.key === "M") && e.ctrlKey) {
          e.preventDefault()
          this.pushEvent("toggle_input_mode")
        }
      })
    },
    updated() {
      this.resize()
    },
    resize() {
      this.el.style.height = "auto"
      this.el.style.height = Math.min(this.el.scrollHeight, 240) + "px"
    }
  },

  StreamingCursor: {
    mounted() {
      this.cursor = this.createCursor()
      this.insertCursorAtEnd()
    },

    updated() {
      this.insertCursorAtEnd()
    },

    destroyed() {
      if (this.cursor && this.cursor.parentNode) {
        this.cursor.remove()
      }
    },

    createCursor() {
      const cursor = document.createElement("span")
      cursor.className = "terminal-cursor"
      return cursor
    },

    insertCursorAtEnd() {
      // Find the last text node with actual content
      const lastTextNode = this.findLastTextNode(this.el)

      if (lastTextNode) {
        const text = lastTextNode.textContent
        const trimmedLength = text.trimEnd().length

        if (trimmedLength < text.length && trimmedLength > 0) {
          // Has trailing whitespace - split the node
          // "code\n" becomes "code" + "\n", cursor goes between them
          const whitespaceNode = lastTextNode.splitText(trimmedLength)
          lastTextNode.parentNode.insertBefore(this.cursor, whitespaceNode)
        } else {
          // No trailing whitespace, insert after the text node
          const parent = lastTextNode.parentNode
          const nextSibling = lastTextNode.nextSibling

          if (nextSibling) {
            parent.insertBefore(this.cursor, nextSibling)
          } else {
            parent.appendChild(this.cursor)
          }
        }
      } else {
        // No text found, append to container
        this.el.appendChild(this.cursor)
      }
    },

    findLastTextNode(element) {
      // Use TreeWalker to find all text nodes
      const walker = document.createTreeWalker(
        element,
        NodeFilter.SHOW_TEXT,
        {
          acceptNode: (node) => {
            // Skip whitespace-only nodes
            if (node.textContent.trim() === "") {
              return NodeFilter.FILTER_SKIP
            }
            return NodeFilter.FILTER_ACCEPT
          }
        }
      )

      let lastTextNode = null
      while (walker.nextNode()) {
        lastTextNode = walker.currentNode
      }

      return lastTextNode
    }
  },

  ResizablePanes: {
    STORAGE_KEY: "msfailab:pane-width",
    MIN_PERCENT: 20,
    MAX_PERCENT: 80,
    DEFAULT_PERCENT: 50,

    clamp(percent) {
      return Math.min(this.MAX_PERCENT, Math.max(this.MIN_PERCENT, percent))
    },

    applyWidth(percent) {
      this.el.style.setProperty("--left-pane-width", `${percent}%`)
    },

    restoreWidth() {
      const saved = localStorage.getItem(this.STORAGE_KEY)
      const percent = saved ? parseFloat(saved) : this.DEFAULT_PERCENT
      this.applyWidth(this.clamp(percent))
    },

    mounted() {
      // Restore saved width on mount
      this.restoreWidth()

      // Find the divider element
      this.divider = this.el.querySelector("[data-pane-divider]")
      this.leftPane = this.el.querySelector("[data-pane-left]")
      this.rightPane = this.el.querySelector("[data-pane-right]")

      if (!this.divider || !this.leftPane || !this.rightPane) return

      // Drag state
      this.isDragging = false

      const onMouseDown = (e) => {
        this.isDragging = true
        e.preventDefault()
        document.body.style.cursor = "col-resize"
        document.body.style.userSelect = "none"
      }

      const onMouseMove = (e) => {
        if (!this.isDragging) return

        const rect = this.el.getBoundingClientRect()
        const x = e.clientX - rect.left
        const percent = (x / rect.width) * 100
        this.applyWidth(this.clamp(percent))
      }

      const onMouseUp = () => {
        if (!this.isDragging) return
        this.isDragging = false
        document.body.style.cursor = ""
        document.body.style.userSelect = ""

        // Persist to localStorage
        const currentWidth = this.el.style.getPropertyValue("--left-pane-width")
        if (currentWidth) {
          localStorage.setItem(this.STORAGE_KEY, parseFloat(currentWidth))
        }
      }

      // Touch support
      const onTouchStart = (e) => {
        this.isDragging = true
        e.preventDefault()
      }

      const onTouchMove = (e) => {
        if (!this.isDragging || !e.touches[0]) return

        const rect = this.el.getBoundingClientRect()
        const x = e.touches[0].clientX - rect.left
        const percent = (x / rect.width) * 100
        this.applyWidth(this.clamp(percent))
      }

      const onTouchEnd = () => {
        if (!this.isDragging) return
        this.isDragging = false

        const currentWidth = this.el.style.getPropertyValue("--left-pane-width")
        if (currentWidth) {
          localStorage.setItem(this.STORAGE_KEY, parseFloat(currentWidth))
        }
      }

      // Double-click to reset to 50/50
      const onDoubleClick = () => {
        this.applyWidth(this.DEFAULT_PERCENT)
        localStorage.setItem(this.STORAGE_KEY, this.DEFAULT_PERCENT)
      }

      // Attach event listeners
      this.divider.addEventListener("mousedown", onMouseDown)
      this.divider.addEventListener("dblclick", onDoubleClick)
      document.addEventListener("mousemove", onMouseMove)
      document.addEventListener("mouseup", onMouseUp)

      this.divider.addEventListener("touchstart", onTouchStart, { passive: false })
      document.addEventListener("touchmove", onTouchMove)
      document.addEventListener("touchend", onTouchEnd)

      // Cleanup on destroy
      this.cleanup = () => {
        this.divider.removeEventListener("mousedown", onMouseDown)
        this.divider.removeEventListener("dblclick", onDoubleClick)
        document.removeEventListener("mousemove", onMouseMove)
        document.removeEventListener("mouseup", onMouseUp)
        this.divider.removeEventListener("touchstart", onTouchStart)
        document.removeEventListener("touchmove", onTouchMove)
        document.removeEventListener("touchend", onTouchEnd)
      }
    },

    updated() {
      // Restore saved width after LiveView DOM updates
      // This prevents the pane from resetting to 50% when content changes
      this.restoreWidth()
    },

    destroyed() {
      if (this.cleanup) this.cleanup()
    }
  },

  AutoDismissFlash: {
    mounted() {
      // Auto-dismiss flash after 10 seconds
      this.timeout = setTimeout(() => {
        this.el.click() // Clicking the flash dismisses it
      }, 10000)
    },

    destroyed() {
      if (this.timeout) {
        clearTimeout(this.timeout)
      }
    }
  },

  ToolCallBox: {
    mounted() {
      this.setupClickHandlers()
      // Restore state if previously expanded
      if (toolBoxExpandedState.get(this.el.id)) {
        this.expand()
      }
    },

    updated() {
      // Restore expansion state after LiveView DOM patch
      if (toolBoxExpandedState.get(this.el.id)) {
        this.expand()
      }
      this.setupClickHandlers()
    },

    setupClickHandlers() {
      const collapsed = this.el.querySelector('[data-collapsed]')
      const expanded = this.el.querySelector('[data-expanded]')
      const collapseTrigger = this.el.querySelector('[data-collapse-trigger]')

      if (!collapsed || !expanded) return

      // Toggle expansion when clicking collapsed view
      collapsed.addEventListener('click', (e) => {
        // Don't toggle if clicking on an interactive element
        if (e.target.closest('button, a, input, select, textarea')) return
        this.expand()
      })

      // Collapse when clicking the collapse trigger in expanded view
      if (collapseTrigger) {
        collapseTrigger.addEventListener('click', (e) => {
          e.stopPropagation()
          this.collapse()
        })
      }
    },

    expand() {
      toolBoxExpandedState.set(this.el.id, true)
      this.el.setAttribute('data-expanded', 'true')
      const collapsed = this.el.querySelector('[data-collapsed]')
      const expanded = this.el.querySelector('[data-expanded]')
      if (collapsed) collapsed.classList.add('hidden')
      if (expanded) expanded.classList.remove('hidden')
      // Make expanded box block-level on its own row
      this.el.classList.remove('inline-flex', 'float-right')
      this.el.classList.add('block', 'clear-both')
    },

    collapse() {
      toolBoxExpandedState.set(this.el.id, false)
      this.el.setAttribute('data-expanded', 'false')
      const collapsed = this.el.querySelector('[data-collapsed]')
      const expanded = this.el.querySelector('[data-expanded]')
      if (collapsed) collapsed.classList.remove('hidden')
      if (expanded) expanded.classList.add('hidden')
      // Restore inline floating for collapsed box (only if it was originally floating)
      if (this.el.classList.contains('ml-2')) {
        this.el.classList.remove('block', 'clear-both')
        this.el.classList.add('inline-flex', 'float-right')
      }
    }
  },

  AutoScroll: {
    mounted() {
      this.isAtBottom = true
      this.threshold = 20 // pixels from bottom to consider "at bottom"

      // Find the scroll button in parent container
      this.button = this.el.parentElement.querySelector("[data-scroll-button]")

      // Scroll to bottom on mount
      this.scrollToBottom()
      this.updateButtonVisibility()

      // Track scroll position
      this.el.addEventListener("scroll", () => this.handleScroll())

      // Handle button click
      if (this.button) {
        this.button.addEventListener("click", () => {
          this.scrollToBottom()
          this.isAtBottom = true
          this.updateButtonVisibility()
        })
      }
    },

    updated() {
      // Re-find button in case DOM was replaced
      this.button = this.el.parentElement.querySelector("[data-scroll-button]")

      // Auto-scroll on content update if at bottom
      if (this.isAtBottom) {
        this.scrollToBottom()
      }

      // Re-apply button visibility after DOM update
      this.updateButtonVisibility()
    },

    handleScroll() {
      const { scrollTop, scrollHeight, clientHeight } = this.el
      const distanceFromBottom = scrollHeight - scrollTop - clientHeight
      this.isAtBottom = distanceFromBottom <= this.threshold
      this.updateButtonVisibility()
    },

    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight
    },

    updateButtonVisibility() {
      if (this.button) {
        this.button.classList.toggle("hidden", this.isAtBottom)
      }
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

