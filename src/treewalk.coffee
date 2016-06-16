# Droplet Treewalker framework.
#
# Copyright (c) Anthony Bau (dab1998@gmail.com)
# MIT License
helper = require './helper.coffee'
model = require './model.coffee'
parser = require './parser.coffee'

exports.createTreewalkParser = (parse, config, root) ->
  class TreewalkParser extends parser.Parser
    constructor: (@text, @opts = {}) ->
      super

      @lines = @text.split '\n'

    isComment: (text) ->
      text.match(/^\s*\/\/.*$/)

    indentAndCommentMarker: (text) ->
      text.match(/^\s*\/\//)[0]

    markRoot: (context = root) ->
      # We can take multiple parse functions,
      # which will be run in sequence.
      if parse instanceof Array
        for parser in parse
          parseTree = parser.parse(context, @text)

          # Parse
          marker = new TreewalkMarker parser.config, @
          marker.mark parseTree, '', 0
      else
        parseTree = parse.parse(context, @text)

        # Parse
        marker = new TreewalkMarker parse.config, @
        marker.mark parseTree, '', 0

  class TreewalkMarker
    constructor: (@config, @parser) ->

    addSocket: -> @parser.addSocket.apply @parser, arguments
    addBlock: -> @parser.addBlock.apply @parser, arguments
    addIndent: -> @parser.addIndent.apply @parser, arguments

    guessPrefix: (bounds) ->
      votes = {}
      for i in [bounds.start.line + 1..bounds.end.line]
        line = @parser.lines[i]
        prefix = line[0...line.length - line.trimLeft().length]
        votes[prefix] ?= 0
        votes[prefix] += 1
      max = -Infinity; best = ''
      for key, val of votes
        if val > max
          best = key
          max = val
      return best

    det: (rule) ->
      if rule of @config.INDENTS then return 'indent'
      else if rule in @config.SKIPS then return 'skip'
      else if rule in @config.PARENS then return 'parens'
      else return 'block'

    detNode: (node) -> if node.blockified then 'block' else @det(node.type)
    detToken: (node) ->
      if node.type?
        if node.type in @config.SOCKET_TOKENS then 'socket' else 'none'
      else 'none'

    getDropType: (context) -> ({
      'block': 'mostly-value'
      'indent': 'mostly-block'
      'skip': 'mostly-block'
    })[@detNode(context)]

    getColor: (node, rules) ->
      color = @config.COLOR_CALLBACK(@parser.opts, node)
      if color?
        return color
      for el, i in rules by -1
        if el of @config.COLORS_BACKWARD
          return @config.COLORS_BACKWARD[el]
      for el, i in rules
        if el of @config.COLORS_FORWARD
          return @config.COLORS_FORWARD[el]
      return 'violet'

    getShape: (node, rules) ->
      shape = @config.SHAPE_CALLBACK(@parser.opts, node)
      if shape?
        return shape
      for el, i in rules by -1
        if el of @config.SHAPES_BACKWARD
          return @config.SHAPES_BACKWARD[el]
      for el, i in rules
        if el of @config.SHAPES_FORWARD
          return @config.SHAPES_FORWARD[el]
      return 'mostly-block'

    mark: (node, prefix, depth, pass, rules, context, wrap) ->
      unless pass
        context = node.parent
        while context? and @detNode(context) in ['skip', 'parens']
          context = context.parent

      rules ?= []
      rules.push node.type

      # Pass through to child if single-child
      if node.children.length is 1
        @mark node.children[0], prefix, depth, true, rules, context, wrap

      else if node.children.length > 0
        switch @detNode node
          when 'block'
            if wrap?
              bounds = wrap.bounds
            else
              bounds = node.bounds

            if context? and @detNode(context) is 'block'
              @addSocket
                bounds: bounds
                depth: depth
                classes: rules
                parseContext: (if wrap? then wrap.type else rules[0])

            @addBlock
              bounds: bounds
              depth: depth + 1
              color: @getColor node, rules
              classes: rules.concat(if context? then @getDropType(context) else @getShape(node, rules))
              parseContext: (if wrap? then wrap.type else rules[0])

          when 'parens'
            # Parens are assumed to wrap the only child that has children
            child = null; ok = true
            for el, i in node.children
              if el.children.length > 0
                if child?
                  ok = false
                  break
                else
                  child = el
            if ok
              @mark child, prefix, depth, true, rules, context, wrap ? node
              return

            else
              node.blockified = true

              if wrap?
                bounds = wrap.bounds
              else
                bounds = node.bounds

              if context? and @detNode(context) is 'block'
                @addSocket
                  bounds: bounds
                  depth: depth
                  classes: rules
                  parseContext: (if wrap? then wrap.type else rules[0])

              @addBlock
                bounds: bounds
                depth: depth + 1
                color: @getColor node, rules
                classes: rules.concat(if context? then @getDropType(context) else @getShape(node, rules))
                parseContext: (if wrap? then wrap.type else rules[0])

          when 'indent' then if @det(context) is 'block'
            start = origin = node.children[0].bounds.start
            for child, i in node.children
              if child.children.length > 0
                break
              else unless helper.clipLines(@parser.lines, origin, child.bounds.end).trim().length is 0
                #console.log 'excluding start', helper.clipLines(@parser.lines, origin, child.bounds.end)
                start = child.bounds.end

            end = node.children[node.children.length - 1].bounds.end
            for child, i in node.children by -1
              if child.children.length > 0
                end = child.bounds.end
                break

            bounds = {
              start: start
              end: end
            }

            oldPrefix = prefix
            prefix = @guessPrefix bounds

            @addIndent
              bounds: bounds
              depth: depth
              prefix: prefix[oldPrefix.length...prefix.length]
              classes: rules
              parseContext: @config.INDENTS[node.type]

        for child in node.children
          @mark child, prefix, depth + 2, false
      else if context? and @detNode(context) is 'block'
        if @detToken(node) is 'socket' and @config.SHOULD_SOCKET(@parser.opts, node)
          @addSocket
            bounds: node.bounds
            depth: depth
            classes: rules
            parseContext: (if wrap? then wrap.type else rules[0])

  TreewalkParser.drop = (block, context, pred) ->
    if context.type is 'socket'
      for c in context.classes
        if c in block.classes
          return helper.ENCOURAGE

        # Check to see if we could paren-wrap this
        if config.parenRules? and c of config.parenRules
          for m in block.classes
            if m of config.parenRules[c]
              return helper.ENCOURAGE

      return helper.DISCOURAGE

  # Doesn't yet deal with parens
  TreewalkParser.parens = (leading, trailing, node, context)->
    # If we're moving to null, remove parens (where possible)
    unless context?
      if config.unParenWrap?
        return config.unParenWrap leading, trailing, node, context
      else
        return


    # If we already match types, we're fine
    for c in context.classes
      if c in node.classes
        return

    # Otherwise, wrap according to the provided rule
    for c in context.classes when c of config.parenRules
      for m in node.classes when m of config.parenRules[c]
        return config.parenRules[c][m] leading, trailing, node, context

  return TreewalkParser
