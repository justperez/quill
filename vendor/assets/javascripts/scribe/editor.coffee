doSilently = (fn) ->
  oldIgnoreDomChange = @ignoreDomChanges
  @ignoreDomChanges = true
  fn()
  @ignoreDomChanges = oldIgnoreDomChange

initListeners = ->
  onEditOnce = =>
  onEdit = =>
    onEditOnce = _.once(onEdit)
    return if @ignoreDomChanges
    update.call(this)
  onSubtreeModified = =>
    return if @ignoreDomChanges
    toCall = onEditOnce
    _.defer( =>
      toCall.call(null)
    )
  onEditOnce = _.once(onEdit)
  @root.addEventListener('DOMSubtreeModified', onSubtreeModified)

keepNormalized = (fn) ->
  fn.call(this)
  @doc.rebuildDirty()
  @doc.forceTrailingNewline()

trackDelta = (fn) ->
  oldDelta = @doc.toDelta()
  fn()
  newDelta = @doc.toDelta()
  decompose = newDelta.decompose(oldDelta)
  compose = oldDelta.compose(decompose)
  console.assert(compose.isEqual(newDelta), oldDelta, newDelta, decompose, compose)
  @undoManager.record(decompose, oldDelta)
  this.emit(ScribeEditor.events.TEXT_CHANGE, decompose) unless decompose.isIdentity()
  return decompose

update = ->
  doSilently.call(this, =>
    @selection.preserve( =>
      return trackDelta.call(this, =>
        Scribe.Document.normalizeHtml(@root)
        lines = @doc.lines.toArray()
        lineNode = @root.firstChild
        _.each(lines, (line, index) =>
          while line.node != lineNode
            if line.node.parentNode == @root
              newLine = @doc.insertLineBefore(lineNode, line)
              lineNode = lineNode.nextSibling
            else
              @doc.removeLine(line)
              return
          @doc.updateLine(line)
          lineNode = lineNode.nextSibling
        )
        while lineNode != null
          newLine = @doc.appendLine(lineNode)
          lineNode = lineNode.nextSibling
      )
    )
  )


class ScribeEditor extends EventEmitter2
  @editors: []

  @CONTAINER_ID: 'scribe-container'
  @ID_PREFIX: 'editor-'
  @CURSOR_PREFIX: 'cursor-'
  @DEFAULTS:
    cursor: 0
    enabled: true
    styles: {}
  @events: 
    TEXT_CHANGE      : 'text-change'
    SELECTION_CHANGE : 'selection-change'

  constructor: (@iframeContainer, options) ->
    @options = _.extend(Scribe.Editor.DEFAULTS, options)
    @id = _.uniqueId(ScribeEditor.ID_PREFIX)
    @iframeContainer = document.getElementById(@iframeContainer) if _.isString(@iframeContainer)
    this.reset(true)
    this.enable() if @options.enabled

  reset: (keepHTML = false) ->
    @ignoreDomChanges = true
    options = _.clone(@options)
    options.keepHTML = keepHTML
    @renderer = new Scribe.Renderer(@iframeContainer, options)
    @contentWindow = @renderer.iframe.contentWindow
    @root = @contentWindow.document.getElementById(ScribeEditor.CONTAINER_ID)
    @doc = new Scribe.Document(@root)
    @selection = new Scribe.Selection(this)
    @keyboard = new Scribe.Keyboard(this)
    @undoManager = new Scribe.UndoManager(this)
    @pasteManager = new Scribe.PasteManager(this)
    initListeners.call(this)
    @ignoreDomChanges = false
    ScribeEditor.editors.push(this)

  disable: ->
    doSilently.call(this, =>
      @root.setAttribute('contenteditable', false)
    )

  enable: ->
    if !@root.getAttribute('contenteditable')
      doSilently.call(this, =>
        @root.setAttribute('contenteditable', true)
      )

  applyDelta: (delta, external = true) ->
    # Make exception for systems that assume editors start with empty text
    if delta.startLength == 0 and @doc.length == 1 and @doc.trailingNewline
      return this.setDelta(delta)
    return if delta.isIdentity()
    doSilently.call(this, =>
      @selection.preserve( =>
        console.assert(delta.startLength == @doc.length, "Trying to apply delta to incorrect doc length", delta, @doc, @root)
        oldDelta = @doc.toDelta()
        delta.apply(@doc.insertText, @doc.deleteText, @doc.formatText, @doc)
        # If we had to force newline, pretend user added it
        if @doc.forceTrailingNewline()
          addNewlineDelta = new Tandem.Delta(delta.endLength, [
            new Tandem.RetainOp(0, delta.endLength)
            new Tandem.InsertOp("\n")
          ])
          this.emit(ScribeEditor.events.TEXT_CHANGE, addNewlineDelta)
          delta = delta.compose(addNewlineDelta)
        @undoManager.record(delta, oldDelta)
        unless external
          this.emit(ScribeEditor.events.TEXT_CHANGE, delta)
        console.assert(delta.endLength == this.getLength(), "Applying delta resulted in incorrect end length", delta, this.getLength())
      )
    )

  deleteAt: (index, length) ->
    doSilently.call(this, =>
      @selection.preserve( =>
        return trackDelta.call(this, =>
          keepNormalized.call(this, =>
            @doc.deleteText(index, length)
          )
        )
      )
    )

  # formatAt: (Number index, Number length, String name, Mixed value) ->
  formatAt: (index, length, name, value) ->
    doSilently.call(this, =>
      @selection.preserve( =>
        return trackDelta.call(this, =>
          keepNormalized.call(this, =>
            @doc.formatText(index, length, name, value)
          )
        )
      )
    )

  getDelta: ->
    return @doc.toDelta()

  getLength: ->
    return @doc.length

  getSelection: ->
    return @selection.getRange()

  insertAt: (index, text) ->
    doSilently.call(this, =>
      @selection.preserve( =>
        return trackDelta.call(this, =>
          keepNormalized.call(this, =>
            @doc.insertText(index, text)
          )
        )
      )
    )

  setDelta: (delta) ->
    oldLength = delta.startLength
    delta.startLength = @doc.length
    this.applyDelta(delta)
    delta.startLength = oldLength
    
  setSelection: (range) ->
    @selection.setRange(range)



window.Scribe ||= {}
window.Scribe.Editor = ScribeEditor
