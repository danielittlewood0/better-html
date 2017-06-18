require 'better_html/test_helper/ruby_expr'
require_relative 'safety_tester_base'

module BetterHtml
  module TestHelper
    module SafeErbTester
      include SafetyTesterBase

      SAFETY_TIPS = <<-EOF
-----------

The javascript snippets listed above do not appear to be escaped properly
in a javascript context. Here are some tips:

Never use html_safe inside a html tag, since it is _never_ safe:
  <a href="<%= value.html_safe %>">
                    ^^^^^^^^^^

Always use .to_json for html attributes which contain javascript, like 'onclick',
or twine attributes like 'data-define', 'data-context', 'data-eval', 'data-bind', etc:
  <div onclick="<%= value.to_json %>">
                         ^^^^^^^^

Always use raw and to_json together within <script> tags:
  <script type="text/javascript">
    var yourValue = <%= raw value.to_json %>;
  </script>             ^^^      ^^^^^^^^

-----------
EOF

      def assert_erb_safety(data, **options)
        tester = Tester.new(data, **options)

        message = ""
        tester.errors.each do |error|
          message << format_safety_error(data, error)
        end

        message << SAFETY_TIPS

        assert_predicate tester.errors, :empty?, message
      end

      private

      class Tester
        attr_reader :errors

        VALID_JAVASCRIPT_TAG_TYPES = ['text/javascript', 'text/template', 'text/html']

        def initialize(data, **options)
          @data = data
          @errors = Errors.new
          @options = options.present? ? options.dup : {}
          @options[:template_language] ||= :html
          @nodes = BetterHtml::NodeIterator.new(data, @options.slice(:template_language))
          validate!
        end

        def add_error(token, message)
          @errors.add(SafetyTesterBase::SafetyError.new(token, message))
        end

        def validate!
          @nodes.each_with_index do |node, index|
            case node
            when BetterHtml::NodeIterator::Element
              validate_element(node)

              if node.name == 'script'
                next_node = @nodes[index + 1]
                if next_node.is_a?(BetterHtml::NodeIterator::ContentNode) && !node.closing?
                  if javascript_tag_type?(node, "text/javascript")
                    validate_script_tag_content(next_node)
                  end
                  validate_no_statements(next_node) unless javascript_tag_type?(node, "text/html")
                end

                validate_javascript_tag_type(node) unless node.closing?
              end
            when BetterHtml::NodeIterator::Text
              if @nodes.template_language == :javascript
                validate_script_tag_content(node)
                validate_no_statements(node)
              else
                validate_no_javascript_tag(node)
              end
            when BetterHtml::NodeIterator::CData, BetterHtml::NodeIterator::Comment
              validate_no_statements(node)
            end
          end
        end

        def javascript_tag_type?(element, which)
          typeattr = element['type']
          value = typeattr&.unescaped_value || "text/javascript"
          value == which
        end

        def validate_javascript_tag_type(element)
          typeattr = element['type']
          return if typeattr.nil?
          if !VALID_JAVASCRIPT_TAG_TYPES.include?(typeattr.unescaped_value)
            add_error(typeattr.value_parts.first, "#{typeattr.value} is not a valid type, valid types are #{VALID_JAVASCRIPT_TAG_TYPES.join(', ')}")
          end
        end

        def validate_element(element)
          element.attributes.each do |attr_token|
            attr_token.value_parts.each do |value_token|
              case value_token.type
              when :expr_literal
                validate_tag_expression(element, attr_token.name, value_token)
              when :expr_escaped
                add_error(value_token, "erb interpolation with '<%==' inside html attribute is never safe")
              end
            end
          end
        end

        def validate_tag_expression(node, attr_name, value_token)
          expr = RubyExpr.new(code: value_token.code)

          if javascript_attribute_name?(attr_name) && expr.calls.empty?
            add_error(value_token, "erb interpolation in javascript attribute must call '(...).to_json'")
            return
          end

          expr.calls.each do |call|
            if call.method == 'raw'
              add_error(value_token, "erb interpolation with '<%= raw(...) %>' inside html attribute is never safe")
            elsif call.method == 'html_safe'
              add_error(value_token, "erb interpolation with '<%= (...).html_safe %>' inside html attribute is never safe")
            elsif javascript_attribute_name?(attr_name) && !javascript_safe_method?(call.method)
              add_error(value_token, "erb interpolation in javascript attribute must call '(...).to_json'")
            end
          end
        end

        def javascript_attribute_name?(name)
          BetterHtml.config.javascript_attribute_names.any?{ |other| other === name }
        end

        def javascript_safe_method?(name)
          BetterHtml.config.javascript_safe_methods.include?(name)
        end

        def validate_script_tag_content(node)
          node.content_parts.each do |token|
            case token.type
            when :expr_literal, :expr_escaped
              expr = RubyExpr.new(code: token.code)
              if expr.calls.empty?
                add_error(token, "erb interpolation in javascript tag must call '(...).to_json'")
              else
                validate_script_expression(node, token, expr)
              end
            end
          end
        end

        def validate_script_expression(node, token, expr)
          expr.calls.each do |call|
            if call.method == 'raw'
              arguments_expr = RubyExpr.new(tree: call.arguments)
              validate_script_expression(node, token, arguments_expr)
            elsif call.method == 'html_safe'
              instance_expr = RubyExpr.new(tree: call.instance)
              validate_script_expression(node, token, instance_expr)
            elsif !javascript_safe_method?(call.method)
              add_error(token, "erb interpolation in javascript tag must call '(...).to_json'")
            end
          end
        end

        def validate_no_statements(node)
          node.content_parts.each do |token|
            if token.type == :stmt && !(/\A\s*end/m === token.code)
              add_error(token, "erb statement not allowed here; did you mean '<%=' ?")
            end
          end
        end

        def validate_no_javascript_tag(node)
          node.content_parts.each do |token|
            if [:stmt, :expr_literal, :expr_escaped].include?(token.type)
              expr = begin
                RubyExpr.new(code: token.code)
              rescue RubyExpr::ParseError
                next
              end
              if expr.calls.size == 1 && expr.calls.first.method == 'javascript_tag'
                add_error(token, "'javascript_tag do' syntax is deprecated; use inline <script> instead")
              end
            end
          end
        end
      end
    end
  end
end
