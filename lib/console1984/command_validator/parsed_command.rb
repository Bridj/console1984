# Parses a command string and exposes different constructs to be used by validations.
#
# Internally, it uses the {parser}[https://github.com/whitequark/parser] gem to perform the parsing.
class Console1984::CommandValidator::ParsedCommand
  include Console1984::Freezeable

  attr_reader :raw_command

  delegate :declared_classes_or_modules, :constants, :constant_assignments, to: :processed_ast

  def initialize(raw_command)
    @raw_command = Array(raw_command).join("\n")
  end

  private
    def processed_ast
      @processed_ast ||= CommandProcessor.new.tap do |processor|
        ast = Parser::CurrentRuby.parse(raw_command)
        processor.process(ast)
      rescue Parser::SyntaxError
        # Fail open with syntax errors
      end
    end

    class CommandProcessor < ::Parser::AST::Processor
      include AST::Processor::Mixin
      include Console1984::Freezeable

      def initialize
        @constants = []
        @declared_classes_or_modules = []
        @constant_assignments = []
      end

      # We define accessors to define lists without duplicates. We are not using a +SortedSet+ because we want
      # to mutate strings in the list while the processing is happening. And we don't use metapgroamming to define the
      # accessors to prevent having problems with freezable and its instance_variable* protection.

      def constants
        @constants.uniq
      end

      def declared_classes_or_modules
        @declared_classes_or_modules.uniq
      end

      def constant_assignments
        @constant_assignments.uniq
      end

      def on_class(node)
        super
        const_declaration, _, _ = *node
        constant = extract_constants(const_declaration).first
        @declared_classes_or_modules << constant if constant.present?
      end

      alias_method :on_module, :on_class

      def on_const(node)
        super
        name, const_name = *node
        const_name = const_name.to_s
        last_constant = @constants.last

        if name.nil? || (name && name.type == :cbase) # cbase = leading ::
          if last_constant&.end_with?("::")
            last_constant << const_name
          else
            @constants << const_name
          end
        elsif last_constant
          last_constant << "::#{const_name}"
        end
      end

      def on_casgn(node)
        super
        _scope_node, name, value_node = *node
        @constant_assignments.push(*extract_constants(value_node))
      end

      private
        def extract_constants(node)
          self.class.new.tap do |processor|
            processor.process(node)
          end.constants
        end
    end
end
