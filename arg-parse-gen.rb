#TODO: Need to generate help message
#TODO: Need to add switch for showing help message

class BashArgParserGenerator

  class ArgumentOptions

    def initialize(argument_name, opts = {})
      @opts = opts
      @argument_name = argument_name
    end

    def required?
      @opts[:required]
    end

    def validate
      if @opts.empty?
        raise StandardError, "Argument options can not be empty."
      end
      if @opts[:description].nil?
        raise StandardError, "Must provide description for all arguments with :description."
      end
      if @opts[:boolean] && (@opts[:required] || @opts[:validation])
        raise StandardError, "Boolean arguments can not be required or have validation code."
      end
      if (validation = @opts[:validation]) && !validation[/\$arg/]
        raise StandardError, 'Validation code needs to have a placeholder called $arg where the argument will be spliced.'
      end
      self
    end

    def generate_validation_code
      validation_code = []
      if (validation = @opts[:validation])
        ["    if [[ \"$current_argument\" = \"--#{@argument_name}\" ]]; then",
         "      if [[ ! $(#{validation}) ]]; then",
         '        echo Argument value validation failed for "$current_argument": "$arg".',
         '        exit 1',
         '      fi',
         '    fi'].reduce(validation_code) {|m, line| m << line; m}
      end
      validation_code
    end

    ##
    # Generate the state machine for this argument as a sequence of bash if statements.

    def generate_bash_sequence
      accumulator = [
         "    if [[ \"$arg\" = \"--#{@argument_name}\" ]]; then",
         '      if [[ "$current_argument" ]]; then',
         '        echo We were already parsing an argument: $current_argument.',
         '        echo We were looking for a value but saw another argument: $arg.',
         '        exit 1',
         '      fi']
      if @opts[:boolean]
        addendum = [
         "      arguments[\"#{@argument_name}\"]=true",
         '      multi_arg=false',
         ]
      elsif @opts[:multi]
        addendum = [
         '      multi_arg=true',
         "      current_argument=\"#{@argument_name}\"",
        ]
      else
        addendum = [
         "      current_argument=\"#{@argument_name}\"",
         '      multi_arg=false',
         ]
      end
      addendum.reduce(accumulator) {|m, line| m << line; m}
      accumulator << '      continue'
      accumulator << '    fi'
      accumulator
    end

  end

  ##
  # The entry point for describing the arguments.

  def self.arguments(&blk)
    inst = self.new
    inst.instance_eval do
      (class << self; self; end).instance_eval do
        define_method(:build, &blk)
      end
    end
    inst.build
    inst
  end

  ##
  # Self-explanatory.

  def initialize
    @arguments = {}
  end

  ##
  # Name is a symbol or a string and underscores are converted to dashes when
  # we generate the bash function for parsing the arguments. We make sure that
  # there are no spaces in the name to simplify the generated bash function.
  # The set of options can include :validation, which needs to be a single line
  # bash command with a placeholder symbol. The placeholder symbol is $arg.

  def argument(name, opts = {})
    string_name = name.to_s
    if string_name[/  /]
      raise StandadError, "Argument name can not contain spaces."
    end
    if string_name[/__/]
      raise StandardError, "Argument name can not contain two underscores in a row."
    end
    if string_name.downcase != string_name
      raise StandardError, "Argument name must be all lowercase."
    end
    canonical_name = string_name.gsub('_', '-')
    if @arguments[canonical_name]
      raise StandardError, "Can not define the same argument twice: #{canonical_name}."
    end
    @arguments[canonical_name] = ArgumentOptions.new(canonical_name, opts).validate
  end

  ##
  # Assume we have associative arrays, i.e. hash maps, when generating the parsing
  # function.

  def generate_bash_function
    bash_function = []
    emit = lambda {|code| bash_function << code}
    emit['declare -A arguments']
    emit['function argument_parser() {']
    emit['  local current_argument']
    emit['  local multi_arg']
    emit['  local function_arguments']
    emit['  function_arguments=("$@")']
    emit['  for arg in "${function_arguments[@]}"; do']
    @arguments.each do |argument_name, argument_options|
      argument_options.generate_bash_sequence.each {|line| emit[line]}
    end
    @arguments.each do |argument_name, argument_options|
      argument_options.generate_validation_code.each {|line| emit[line]}
    end
    emit['    if [[ ! "$current_argument" ]]; then']
    emit['      echo current_argument is not set.']
    emit['      echo Make sure the first argument is actually specified with --[ARGUMENT NAME]']
    emit['      exit 1']
    emit['    fi']
    emit['    if [[ $multi_arg ]]; then']
    emit['      if [[ ! ${arguments["$current_argument"]} ]]; then']
    emit['        arguments["$current_argument"]=""']
    emit['      fi']
    emit['      arguments["$current_argument"]+="$arg "']
    emit['      continue']
    emit['    fi']
    emit['    arguments["$current_argument"]="$arg"']
    emit['    current_argument=""']
    emit['    multi_arg=false']
    emit['  done']
    @arguments.each do |argument_name, argument_options|
      if argument_options.required?
        emit["  if [[ ! arguments[\"#{argument_name}\"] ]]; then"]
        emit["    echo Went through the entire argument array and did not find a required parameter: \\'--#{argument_name}\\'."]
        emit['    exit 1']
        emit['  fi']
      end
    end
    emit['}']
    bash_function.join("\n")
  end

end
