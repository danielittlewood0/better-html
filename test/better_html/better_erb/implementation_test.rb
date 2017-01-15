require 'test_helper'
require 'ostruct'
require 'better_html/better_erb'
require 'json'

class BetterHtml::BetterErb::ImplementationTest < ActiveSupport::TestCase
  test "simple template rendering" do
    assert_equal "<foo>some value<foo>",
      render("<foo><%= bar %><foo>", { bar: 'some value' })
  end

  test "html_safe interpolation" do
    assert_equal "<foo><bar /><foo>",
      render("<foo><%= bar %><foo>", { bar: '<bar />'.html_safe })
  end

  test "non html_safe interpolation" do
    assert_equal "<foo>&lt;bar /&gt;<foo>",
      render("<foo><%= bar %><foo>", { bar: '<bar />' })
  end

  test "interpolate non-html_safe inside attribute is escaped" do
    assert_equal "<a href=\" &#39;&quot;&gt;x \">",
      render("<a href=\"<%= value %>\">", { value: ' \'">x ' })
  end

  test "interpolate html_safe inside attribute is magically force-escaped" do
    assert_equal "<a href=\" &#39;&quot;&gt;x \">",
      render("<a href=\"<%= value %>\">", { value: ' \'">x '.html_safe })
  end

  test "interpolate html_safe inside single quoted attribute" do
    assert_equal "<a href=\' &#39;&quot;&gt;x \'>",
      render("<a href=\'<%= value %>\'>", { value: ' \'">x '.html_safe })
  end

  test "interpolate in attribute name" do
    assert_equal "<a data-safe-foo>",
      render("<a data-<%= value %>-foo>", { value: "safe" })
  end

  test "interpolate in attribute name with unsafe value with spaces" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<a data-<%= value %>-foo>", { value: "un safe" })
    end
    assert_equal "Detected invalid characters as part of the "\
      "interpolation into a attribute name around: <a data-<%= value %>>.", e.message
  end

  test "interpolate in attribute name with unsafe value with equal sign" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<a data-<%= value %>-foo>", { value: "un=safe" })
    end
    assert_equal "Detected invalid characters as part of the "\
      "interpolation into a attribute name around: <a data-<%= value %>>.", e.message
  end

  test "interpolate in attribute name with unsafe value with quote" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<a data-<%= value %>-foo>", { value: "un\"safe" })
    end
    assert_equal "Detected invalid characters as part of the "\
      "interpolation into a attribute name around: <a data-<%= value %>>.", e.message
  end

  test "interpolate in attribute without quotes" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<a href=<%= value %>>", { value: "un safe" })
    end
    assert_equal "Detected invalid characters as part of the "\
      "interpolation into a attribute name around: <a href<%= value %>>.", e.message
  end

  test "interpolate in attribute after value" do
    e = assert_raises(BetterHtml::DontInterpolateHere) do
      render("<a href=something<%= value %>>", { value: "" })
    end
    assert_equal "Do not interpolate without quotes around this "\
      "attribute value. Instead of <a href=something<%= value %>> "\
      "try <a href=\"something<%= value %>\">.", e.message
  end

  test "interpolate in tag name" do
    assert_equal "<tag-safe-foo>",
      render("<tag-<%= value %>-foo>", { value: "safe" })
  end

  test "interpolate in tag name with space" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<tag-<%= value %>-foo>", { value: "un safe" })
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a tag name around: <tag-<%= value %>>.", e.message
  end

  test "interpolate in tag name with slash" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<tag-<%= value %>-foo>", { value: "un/safe" })
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a tag name around: <tag-<%= value %>>.", e.message
  end

  test "interpolate in tag name with end of tag" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<tag-<%= value %>-foo>", { value: "><script>" })
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a tag name around: <tag-<%= value %>>.", e.message
  end

  test "interpolate in comment" do
    assert_equal "<!-- safe -->",
      render("<!-- <%= value %> -->", { value: "safe" })
  end

  test "interpolate in comment with end-of-comment" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<!-- <%= value %> -->", { value: "-->".html_safe })
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a html comment around: <!-- <%= value %>.", e.message
  end

  test "non html_safe interpolation into comment tag" do
    assert_equal "<!-- --&gt; -->",
      render("<!-- <%= value %> -->", value: '-->')
  end

  test "interpolate in script tag" do
    assert_equal "<script> foo safe bar<script>",
      render("<script> foo <%= value %> bar<script>", { value: "safe" })
  end

  test "interpolate in script tag with start of comment" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<script> foo <%= value %> bar<script>", { value: "<!--".html_safe })
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a script tag around: <script> foo <%= value %>.", e.message
  end

  test "interpolate in script tag with start of script" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<script> foo <%= value %> bar<script>", { value: "<script".html_safe })
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a script tag around: <script> foo <%= value %>.", e.message
  end

  test "interpolate in script tag with raw interpolation" do
    assert_equal "<script> x = \"foo\" </script>",
      render("<script> x = <%== value %> </script>", { value: JSON.dump("foo") })
  end

  test "interpolate in script tag with start of script case insensitive" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<script> foo <%= value %> bar<script>", { value: "<ScRIpT".html_safe })
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a script tag around: <script> foo <%= value %>.", e.message
  end

  test "interpolate in script tag with end of script" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<script> foo <%= value %> bar<script>", { value: "</script".html_safe })
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a script tag around: <script> foo <%= value %>.", e.message
  end

  test "interpolate html_attributes" do
    assert_equal "<a foo=\"bar\">",
      render("<a <%= html_attributes(foo: 'bar') %>>")
  end

  test "interpolate without html_attributes" do
    e = assert_raises(BetterHtml::DontInterpolateHere) do
      render("<a <%= 'foo=\"bar\"' %>>")
    end
    assert_equal "Do not interpolate String in a tag. Instead "\
      "of <a <%= 'foo=\"bar\"' %>> please try <a <%= html_attributes(attr: value) %>>.", e.message
  end

  test "non html_safe interpolation into rawtext tag" do
    assert_equal "<title>&lt;/title&gt;</title>",
      render("<title><%= value %></title>", value: '</title>')
  end

  test "html_safe interpolation into rawtext tag" do
    assert_equal "<title><safe></title>",
      render("<title><%= value %></title>", value: '<safe>'.html_safe)
  end

  test "html_safe interpolation terminating the current tag" do
    e = assert_raises(BetterHtml::UnsafeHtmlError) do
      render("<title><%= value %></title>", value: '</title>'.html_safe)
    end
    assert_equal "Detected invalid characters as part of the interpolation "\
      "into a title tag around: <title><%= value %>.", e.message
  end

  test "interpolate block in middle of tag" do
    e = assert_raises(BetterHtml::DontInterpolateHere) do
      render(<<-HTML)
        <a href="" <%= something do %>
          foo
        <% end %>
      HTML
    end
    assert_equal "Block not allowed at this location.", e.message
  end

  test "interpolate with output block is valid syntax" do
    assert_nothing_raised do
      render(<<-HTML)
        <%= capture do %>
          <foo>
        <% end %>
      HTML
    end
  end

  test "interpolate with statement block is valid syntax" do
    assert_nothing_raised do
      render(<<-HTML)
        <% capture do %>
          <foo>
        <% end %>
      HTML
    end
  end

  test "can interpolate method calls without parenthesis" do
    assert_equal "<div>foo</div>",
      render("<div><%= send 'value' %></div>", value: 'foo')
  end

  test "capture works as intended" do
    puts "dfsfsdsfdfsd"
    output = render(<<-HTML)
      <%- foo = capture do -%>
        <foo>
      <%- end -%>
      <bar><%= foo %></bar>
    HTML

    assert_equal "      <bar>        <foo>\n</bar>\n", output
  end

  private

  def render(source, locals={})
    src = compile(source)
    context = OpenStruct.new(locals)
    context.extend(ActionView::Helpers)
    context.extend(BetterHtml::Helpers)
    context.class_eval do
      attr_accessor :output_buffer
    end
    context.instance_eval(src)
  end

  def compile(source)
    BetterHtml::BetterErb::Implementation.new(source).src
  end
end