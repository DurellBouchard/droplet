# Droplet C mode
#
# Copyright (c) 2015 Anthony Bau
# MIT License

parser = require '../parser.coffee'
antlrHelper = require '../antlr.coffee'

INDENTS = {
  'compoundStatement': 'blockItem',
  'structDeclarationsBlock': 'structDeclaration'
}
SKIPS = ['blockItemList',
  'macroParamList',
  'compilationUnit',
  'translationUnit',
  'declarationSpecifiers',
  'declarationSpecifier',
  'typeSpecifier',
  'structOrUnionSpecifier',
  'structDeclarationList',
  'declarator',
  'directDeclarator',
  'parameterTypeList',
  'parameterList',
  'argumentExpressionList',
  'initDeclaratorList']
PARENS = ['expressionStatement', 'primaryExpression', 'structDeclaration']
SOCKET_TOKENS = ['Identifier', 'StringLiteral', 'SharedIncludeLiteral', 'Constant']
COLORS_FORWARD = {
  'externalDeclaration': 'control'
  'structDeclaration': 'command'
  'declarationSpecifier': 'control'
  'statement': 'command'
  'selectionStatement': 'control'
  'iterationStatement': 'control'
  'functionDefinition': 'control'
  'expressionStatement': 'command'
  'expression': 'value'
  'additiveExpression': 'value'
  'multiplicativeExpression': 'value'
  'declaration': 'command'
  'parameterDeclaration': 'command'
  'unaryExpression': 'value'
  'typeName': 'value'
}
COLORS_BACKWARD = {
  'iterationStatement': 'control'
  'selectionStatement': 'control'
  'assignmentExpression': 'command'
  'relationalExpression': 'value'
  'initDeclarator': 'command'
}
SHAPES_FORWARD = {
  'externalDeclaration': 'block-only'
  'structDeclaration': 'block-only'
  'declarationSpecifier': 'block-only'
  'statement': 'block-only'
  'selectionStatement': 'block-only'
  'iterationStatement': 'block-only'
  'functionDefinition': 'block-only'
  'expressionStatement': 'value-only'
  'expression': 'value-only'
  'additiveExpression': 'value-only'
  'multiplicativeExpression': 'value-only'
  'declaration': 'block-only'
  'parameterDeclaration': 'block-only'
  'unaryExpression': 'value-only'
  'typeName': 'value-only'
}
SHAPES_BACKWARD = {
  'equalityExpression': 'value-only'
  'logicalAndExpression': 'value-only'
  'logicalOrExpression': 'value-only'
  'iterationStatement': 'block-only'
  'selectionStatement': 'block-only'
  'assignmentExpression': 'block-only'
  'relationalExpression': 'value-only'
  'initDeclarator': 'block-only'
}

config = {
  INDENTS, SKIPS, PARENS, SOCKET_TOKENS, COLORS_FORWARD, COLORS_BACKWARD, SHAPES_FORWARD, SHAPES_BACKWARD
}

preConfig = {
  INDENTS: {}, SKIPS: ['compilationUnit', 'line'], PARENS: [], SOCKET_TOKENS: ['Identifier', 'StringLiteral', 'SharedIncludeLiteral']
  COLOR_CALLBACK: ->
  SHAPE_CALLBACK: ->
  SHOULD_SOCKET: -> true
  COLORS_FORWARD: {
    'preprocessorDirective': 'purple'
  }
  COLORS_BACKWARD: {}
  SHAPES_FORWARD: {
    'preprocessorDirective': 'block-only'
  }
  SHAPES_BACKWARD: {
    'preprocessorDirective': 'value-only'
  }
}

config.SHOULD_SOCKET = (opts, node) ->
  return true unless node.parent? and node.parent.parent? and node.parent.parent.parent?
  # If it is a function call, and we are the first child
  if node.parent.type is 'primaryExpression' and
     node.parent.parent.type is 'postfixExpression' and
     node.parent.parent.parent.type is 'postfixExpression' and
     node.parent.parent.parent.children.length in [3, 4] and
     node.parent.parent.parent.children[1].type is 'LeftParen' and
     (node.parent.parent.parent.children[2].type is 'RightParen' or node.parent.parent.parent.children[3]?.type is 'RightParen') and
     node.parent.parent is node.parent.parent.parent.children[0] and
     node.data.text of opts.knownFunctions
    return false
  return true

config.COLOR_CALLBACK = (opts, node) ->
  if node.type is 'postfixExpression' and
     node.children.length in [3, 4] and
     node.children[1].type is 'LeftParen' and
     (node.children[2].type is 'RightParen' or node.children[3]?.type is 'RightParen') and
     node.children[0].children[0].type is 'primaryExpression' and
     node.children[0].children[0].children[0].type is 'Identifier' and
     node.children[0].children[0].children[0].data.text of opts.knownFunctions
    return opts.knownFunctions[node.children[0].children[0].children[0].data.text].color
  return null

config.SHAPE_CALLBACK = (opts, node) ->
  if node.type is 'postfixExpression' and
     node.children.length in [3, 4] and
     node.children[1].type is 'LeftParen' and
     (node.children[2].type is 'RightParen' or node.children[3]?.type is 'RightParen') and
     node.children[0].children[0].type is 'primaryExpression' and
     node.children[0].children[0].children[0].type is 'Identifier' and
     node.children[0].children[0].children[0].data.text of opts.knownFunctions
    return opts.knownFunctions[node.children[0].children[0].children[0].data.text].shape
  return null

masterConfig = {}

ADD_PARENS = (leading, trailing, node, context) ->
  leading '(' + leading()
  trailing trailing() + ')'

masterConfig.parenRules = {
  'primaryExpression': {
    'expression': ADD_PARENS
    'additiveExpression': ADD_PARENS
    'multiplicativeExpression': ADD_PARENS
    'assignmentExpression': ADD_PARENS
    'postfixExpression': ADD_PARENS
  }
}


# TODO Implement removing parentheses at some point
#config.unParenWrap = (leading, trailing, node, context) ->
#  while true
#   if leading().match(/^\s*\(/)? and trailing().match(/\)\s*/)?
#     leading leading().replace(/^\s*\(\s*/, '')
#      trailing trailing().replace(/\s*\)\s*$/, '')
#    else
#      break

# DEBUG
config.unParenWrap = null

removeSourceLines = (tree) ->
  tree.children = tree.children.filter (child) ->
    not (child.type is 'line' and child.children[0].type is 'sourceLine')
  console.log 'Removed source lines, now tree is', tree
  return tree

module.exports = parser.wrapParser antlrHelper.createANTLRParser [
  {
    name: 'C_pre',
    config: preConfig
    postprocess: removeSourceLines
  }
  ,
  {
    name: 'C',
    config
  }
], masterConfig
