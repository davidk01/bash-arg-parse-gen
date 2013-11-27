require './arg-parse-gen'
a = BashArgParserGenerator.arguments do
  argument :regular_arg, :description => "does stuff", :validation => "asdf $arg"
  argument :another_regular_arg, :description => "does other stuff", :validation => 'asdfasf $arg'
  argument :multi_arg, :description => 'multi arg delimited with spaces', :validation => 'multi arg validation $arg', :multi => true
  argument :boolean_arg, :boolean => true, :description => "some switch"
end

puts a.generate_bash_function
