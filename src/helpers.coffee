{calculateSpecificity} = require 'clear-cut'
keyboard = navigator.keyboard
KeyboardLayout = null
keyboard.getLayoutMap().then((map) -> KeyboardLayout = map)

MODIFIERS = new Set(['ctrl', 'alt', 'shift', 'cmd'])
ENDS_IN_MODIFIER_REGEX = /(ctrl|alt|shift|cmd)$/
WHITESPACE_REGEX = /\s+/
KEY_NAMES_BY_KEYBOARD_EVENT_CODE = {
  'Space': 'space',
  'Backspace': 'backspace'
}
NON_CHARACTER_KEY_NAMES_BY_KEYBOARD_EVENT_KEY = {
  'Control': 'ctrl',
  'Meta': 'cmd',
  'ArrowDown': 'down',
  'ArrowUp': 'up',
  'ArrowLeft': 'left',
  'ArrowRight': 'right'
}
NUMPAD_KEY_NAMES_BY_KEYBOARD_EVENT_CODE = {
  'Numpad0': 'numpad0',
  'Numpad1': 'numpad1',
  'Numpad2': 'numpad2',
  'Numpad3': 'numpad3',
  'Numpad4': 'numpad4',
  'Numpad5': 'numpad5',
  'Numpad6': 'numpad6',
  'Numpad7': 'numpad7',
  'Numpad8': 'numpad8',
  'Numpad9': 'numpad9'
}
DIGIT_KEYS_BY_KEYBOARD_EVENT_CODE = {
  'Digit0': '0',
  'Digit1': '1',
  'Digit2': '2',
  'Digit3': '3',
  'Digit4': '4',
  'Digit5': '5',
  'Digit6': '6',
  'Digit7': '7',
  'Digit8': '8',
  'Digit9': '9'
}

LATIN_KEYMAP_CACHE = new WeakMap()
isLatinKeymap = (keymap) ->
  return true unless keymap?

  isLatin = LATIN_KEYMAP_CACHE.get(keymap)
  if isLatin?
    isLatin
  else
    # To avoid exceptions, if the native keymap does not have entries for a key,
    # assume that key is latin.
    isLatin =
      (not keymap.KeyA? or isLatinCharacter(keymap.KeyA.unmodified)) and
      (not keymap.KeyS? or isLatinCharacter(keymap.KeyS.unmodified)) and
      (not keymap.KeyD? or isLatinCharacter(keymap.KeyD.unmodified)) and
      (not keymap.KeyF? or isLatinCharacter(keymap.KeyF.unmodified))
    LATIN_KEYMAP_CACHE.set(keymap, isLatin)
    isLatin

isASCIICharacter = (character) ->
  character? and character.length is 1 and character.charCodeAt(0) <= 127

isLatinCharacter = (character) ->
  character? and character.length is 1 and character.charCodeAt(0) <= 0x024F

isUpperCaseCharacter = (character) ->
  character? and character.length is 1 and character.toLowerCase() isnt character

isLowerCaseCharacter = (character) ->
  character? and character.length is 1 and character.toUpperCase() isnt character

isNumericCharacter = (character) ->
  character? and character.length is 1 and 48 <= character.charCodeAt(0) <= 57

usKeymap = null
usCharactersForKeyCode = (code) ->
  usKeymap ?= require('./us-keymap')
  usKeymap[code]

slovakCmdKeymap = null
slovakQwertyCmdKeymap = null
slovakCmdCharactersForKeyCode = (code, layout) ->
  slovakCmdKeymap ?= require('./slovak-cmd-keymap')
  slovakQwertyCmdKeymap ?= require('./slovak-qwerty-cmd-keymap')

  if layout is 'com.apple.keylayout.Slovak'
    slovakCmdKeymap[code]
  else
    slovakQwertyCmdKeymap[code]

exports.normalizeKeystrokes = (keystrokes) ->
  normalizedKeystrokes = []
  for keystroke in keystrokes.split(WHITESPACE_REGEX)
    if normalizedKeystroke = normalizeKeystroke(keystroke)
      normalizedKeystrokes.push(normalizedKeystroke)
    else
      return false
  normalizedKeystrokes.join(' ')

normalizeKeystroke = (keystroke) ->
  if keyup = isKeyup(keystroke)
    keystroke = keystroke.slice(1)
  keys = parseKeystroke(keystroke)
  return false unless keys

  primaryKey = null
  modifiers = new Set

  for key, i in keys
    if MODIFIERS.has(key)
      modifiers.add(key)
    else
      # only the last key can be a non-modifier
      if i is keys.length - 1
        primaryKey = key
      else
        return false

  if keyup
    primaryKey = primaryKey.toLowerCase() if primaryKey?
  else
    modifiers.add('shift') if isUpperCaseCharacter(primaryKey)

  keystroke = []
  if not keyup or (keyup and not primaryKey?)
    keystroke.push('ctrl') if modifiers.has('ctrl')
    keystroke.push('alt') if modifiers.has('alt')
    keystroke.push('shift') if modifiers.has('shift')
    keystroke.push('cmd') if modifiers.has('cmd')
  keystroke.push(primaryKey) if primaryKey?
  keystroke = keystroke.join('-')
  keystroke = "^#{keystroke}" if keyup
  keystroke

parseKeystroke = (keystroke) ->
  keys = []
  keyStart = 0
  for character, index in keystroke when character is '-'
    if index > keyStart
      keys.push(keystroke.substring(keyStart, index))
      keyStart = index + 1

      # The keystroke has a trailing - and is invalid
      return false if keyStart is keystroke.length
  keys.push(keystroke.substring(keyStart)) if keyStart < keystroke.length
  keys

exports.keystrokeForKeyboardEvent = (event, customKeystrokeResolvers) ->
  {key, code, ctrlKey, altKey, shiftKey, metaKey} = event


  if NUMPAD_KEY_NAMES_BY_KEYBOARD_EVENT_CODE[code]?
    key = NUMPAD_KEY_NAMES_BY_KEYBOARD_EVENT_CODE[code]

  if DIGIT_KEYS_BY_KEYBOARD_EVENT_CODE[code]?
    key = DIGIT_KEYS_BY_KEYBOARD_EVENT_CODE[code]

  if KEY_NAMES_BY_KEYBOARD_EVENT_CODE[code]?
    key = KEY_NAMES_BY_KEYBOARD_EVENT_CODE[code]

  isAltModifiedKey = false
  isNonCharacterKey = key.length > 1
  if isNonCharacterKey
    key = NON_CHARACTER_KEY_NAMES_BY_KEYBOARD_EVENT_KEY[key] ? key.toLowerCase()
    if key is "altgraph" and process.platform is "win32"
      key = "alt"
  else
    key = key.toLowerCase()

    if event.getModifierState('AltGraph') or (process.platform is 'darwin' and altKey)
      # All macOS layouts have an alt-modified character variant for every
      # single key. Therefore, if we always favored the alt variant, it would
      # become impossible to bind `alt-*` to anything. Since `alt-*` bindings
      # are rare and we bind very few by default on macOS, we will only shadow
      # an `alt-*` binding with an alt-modified character variant if it is a
      # basic ASCII character.
      if process.platform is 'darwin' and event.code
        nonAltModifiedKey = nonAltModifiedKeyForKeyboardEvent(event)
        if nonAltModifiedKey and (ctrlKey or metaKey or not isASCIICharacter(key))
          key = nonAltModifiedKey
        else if key isnt nonAltModifiedKey
          altKey = false
          isAltModifiedKey = true
      # Windows layouts are more sparing in their use of AltGr-modified
      # characters, and the U.S. layout doesn't have any of them at all. That
      # means that if an AltGr variant character exists for the current
      # keystroke, it likely to be the intended character, and we always
      # interpret it as such rather than favoring a `ctrl-alt-*` binding
      # intepretation.
      else if process.platform is 'win32' and event.code
        nonAltModifiedKey = nonAltModifiedKeyForKeyboardEvent(event)
        if nonAltModifiedKey and (metaKey or not isASCIICharacter(key))
          key = nonAltModifiedKey
        else if key isnt nonAltModifiedKey
          ctrlKey = false
          altKey = false
          isAltModifiedKey = true
      # Linux has a dedicated `AltGraph` key that is distinct from all other
      # modifiers, including LeftAlt. However, if AltGraph is used in
      # combination with other modifiers, we want to treat it as a modifier and
      # fall back to the non-alt-modified character.
      else if process.platform is 'linux'
        nonAltModifiedKey = nonAltModifiedKeyForKeyboardEvent(event)
        if nonAltModifiedKey and (ctrlKey or altKey or metaKey)
          key = nonAltModifiedKey
          altKey = event.getModifierState('AltGraph')
          isAltModifiedKey = not altKey

  if event.code and key.length is 1
    if not isLatinCharacter(key)
      characters = usCharactersForKeyCode(event.code)
      if event.shiftKey
        key = characters.withShift
      else if characters.unmodified?
        key = characters.unmodified

  keystroke = ''
  if key is 'ctrl' or (ctrlKey and event.type isnt 'keyup')
    keystroke += 'ctrl'

  if key is 'alt' or (altKey and event.type isnt 'keyup')
    keystroke += '-' if keystroke.length > 0
    keystroke += 'alt'

  if key is 'shift' or shiftKey
    keystroke += '-' if keystroke
    keystroke += 'shift'

  if key is 'cmd' or (metaKey and event.type isnt 'keyup')
    keystroke += '-' if keystroke
    keystroke += 'cmd'

  unless MODIFIERS.has(key)
    keystroke += '-' if keystroke
    keystroke += key

  keystroke = normalizeKeystroke("^#{keystroke}") if event.type is 'keyup'

  keystroke

nonAltModifiedKeyForKeyboardEvent = (event) ->
  if event.code and (characters = KeyboardLayout.get(event.code))
    characters

exports.MODIFIERS = MODIFIERS

exports.characterForKeyboardEvent = (event) ->
  event.key if event.key.length is 1 and not (event.ctrlKey or event.metaKey)

exports.calculateSpecificity = calculateSpecificity

exports.isBareModifier = (keystroke) -> ENDS_IN_MODIFIER_REGEX.test(keystroke)

exports.isModifierKeyup = (keystroke) -> isKeyup(keystroke) and ENDS_IN_MODIFIER_REGEX.test(keystroke)

exports.isKeyup = isKeyup = (keystroke) -> keystroke.startsWith('^') and keystroke isnt '^'

exports.keydownEvent = (key, options) ->
  return buildKeyboardEvent(key, 'keydown', options)

exports.keyupEvent = (key, options) ->
  return buildKeyboardEvent(key, 'keyup', options)

exports.getModifierKeys = (keystroke) ->
  keys = keystroke.split('-')
  mod_keys = []
  for key in keys when MODIFIERS.has(key)
    mod_keys.push(key)
  mod_keys


buildKeyboardEvent = (key, eventType, {ctrl, shift, alt, cmd, keyCode, target, location}={}) ->
  ctrlKey = ctrl ? false
  altKey = alt ? false
  shiftKey = shift ? false
  metaKey = cmd ? false
  bubbles = true
  cancelable = true

  event = new KeyboardEvent(eventType, {
    key, ctrlKey, altKey, shiftKey, metaKey, bubbles, cancelable
  })

  if target?
    Object.defineProperty(event, 'target', get: -> target)
    Object.defineProperty(event, 'path', get: -> [target])
  event
