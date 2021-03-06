annotation = ['$filter', ($filter) ->
  link: (scope, elem, attrs, controller) ->
    return unless controller?

    # Bind shift+enter to save
    elem.bind
      keydown: (e) ->
        if e.keyCode == 13 && e.shiftKey
          e.preventDefault()
          scope.save()

    # Publish the controller
    scope.model = controller
  controller: 'AnnotationController'
  priority: 100  # Must run before ngModel
  require: '?ngModel'
  restrict: 'C'
  scope: {}
  templateUrl: 'annotation.html'
]


markdown = ['$filter', '$timeout', ($filter, $timeout) ->
  link: (scope, elem, attr, ctrl) ->
    return unless ctrl?

    input = elem.find('textarea')
    output = elem.find('div')

    # Re-render the markdown when the view needs updating.
    ctrl.$render = ->
      scope.rendered = ($filter 'converter') (ctrl.$viewValue or '')

    # React to the changes to the text area
    input.bind 'blur change keyup', ->
      value = input.attr('value') or ''
      ctrl.$setViewValue value
      scope.$digest()

    # Auto-focus the input box when the widget becomes editable.
    # Re-render when it becomes uneditable.
    scope.$watch 'readonly', (newValue) ->
      if newValue then ctrl.$render() else $timeout -> input.focus()

  require: '?ngModel'
  restrict: 'E'
  scope:
    readonly: '@'
    required: '@'
  templateUrl: 'markdown.html'
]


privacy = ->
  levels = [
    {name: 'Public', permissions:  { 'read': ['group:__world__'] } },
    {name: 'Private', permissions: { 'read': [] } }
  ]

  getLevel = (permissions) ->
    return unless permissions?

    for level in levels
      roleSet = {}

      # Construct a set (using a key->exist? mapping) of roles for each verb
      for verb of permissions
        roleSet[verb] = {}
        for role in permissions[verb]
          roleSet[verb][role] = true

      # Check that no (verb, role) is missing from the role set
      mismatch = false
      for verb of level.permissions
        for role in level.permissions[verb]
          if roleSet[verb]?[role]?
            delete roleSet[verb][role]
          else
            mismatch = true
            break

        # Check that no extra (verb, role) is missing from the privacy level
        mismatch ||= Object.keys(roleSet[verb]).length
        if mismatch then break else return level

    # Unrecognized privacy level
    name: 'Custom'
    value: permissions

  link: (scope, elem, attrs, controller) ->
    return unless controller?
    controller.$formatters.push getLevel
    controller.$parsers.push (privacy) -> privacy?.permissions
    scope.model = controller
    scope.levels = levels
  require: '?ngModel'
  restrict: 'E'
  scope: true
  templateUrl: 'privacy.html'


recursive = ['$compile', '$timeout', ($compile, $timeout) ->
  compile: (tElement, tAttrs, transclude) ->
    placeholder = angular.element '<!-- recursive -->'
    attachQueue = []
    tick = false

    template = tElement.contents().clone()
    tElement.html ''

    transclude = $compile template, (scope, cloneAttachFn) ->
      clone = placeholder.clone()
      cloneAttachFn clone
      $timeout ->
        transclude scope, (el, scope) -> attachQueue.push [clone, el]
        unless tick
          tick = true
          requestAnimationFrame ->
            tick = false
            for [clone, el] in attachQueue
              clone.after el
              clone.bind '$destroy', -> el.remove()
            attachQueue = []
      clone
    post: (scope, iElement, iAttrs, controller) ->
      transclude scope, (contents) -> iElement.append contents
  restrict: 'A'
  terminal: true
]


resettable = ->
  compile: (tElement, tAttrs, transclude) ->
    post: (scope, iElement, iAttrs) ->
      reset = ->
        transclude scope, (el) ->
          iElement.replaceWith el
          iElement = el
      reset()
      scope.$on '$reset', reset
  priority: 5000
  restrict: 'A'
  transclude: 'element'


###
# The slow validation directive ties an to a model controller and hides
# it while the model is being edited. This behavior improves the user
# experience of filling out forms by delaying validation messages until
# after the user has made a mistake.
###
slowValidate = ['$parse', '$timeout', ($parse, $timeout) ->
  link: (scope, elem, attr, ctrl) ->
    return unless ctrl?

    promise = null

    elem.addClass 'slow-validate'

    ctrl[attr.slowValidate]?.$viewChangeListeners?.push (value) ->
      elem.removeClass 'slow-validate-show'

      if promise
        $timeout.cancel promise
        promise = null

      promise = $timeout -> elem.addClass 'slow-validate-show'

  require: '^form'
  restrict: 'A'
]


tabReveal = ['$parse', ($parse) ->
  compile: (tElement, tAttrs, transclude) ->
    panes = []
    hiddenPanesGet = $parse tAttrs.tabReveal

    pre: (scope, iElement, iAttrs, [ngModel, tabbable] = controller) ->
      # Hijack the tabbable controller's addPane so that the visibility of the
      # secret ones can be managed. This avoids traversing the DOM to find
      # the tab panes.
      addPane = tabbable.addPane
      tabbable.addPane = (element, attr) =>
        removePane = addPane.call tabbable, element, attr
        panes.push
          element: element
          attr: attr
        =>
          for i in [0..panes.length]
            if panes[i].element is element
              panes.splice i, 1
              break
          removePane()

    post: (scope, iElement, iAttrs, [ngModel, tabbable] = controller) ->
      tabs = angular.element(iElement.children()[0].childNodes)
      render = angular.bind ngModel, ngModel.$render

      ngModel.$render = ->
        render()
        hiddenPanes = hiddenPanesGet scope
        return unless angular.isArray hiddenPanes

        for i in [0..panes.length-1]
          pane = panes[i]
          value = pane.attr.value || pane.attr.title
          if value == ngModel.$viewValue
            pane.element.css 'display', ''
            angular.element(tabs[i]).css 'display', ''
          else if value in hiddenPanes
            pane.element.css 'display', 'none'
            angular.element(tabs[i]).css 'display', 'none'
  require: ['ngModel', 'tabbable']
]


thread = ->
  link: (scope, iElement, iAttrs, controller) ->
    scope.collapsed = false
  restrict: 'C'
  scope: true


angular.module('h.directives', ['ngSanitize'])
  .directive('annotation', annotation)
  .directive('markdown', markdown)
  .directive('privacy', privacy)
  .directive('recursive', recursive)
  .directive('resettable', resettable)
  .directive('slowValidate', slowValidate)
  .directive('tabReveal', tabReveal)
  .directive('thread', thread)
