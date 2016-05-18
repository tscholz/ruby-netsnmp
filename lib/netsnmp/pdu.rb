require 'forwardable'
module NETSNMP
  # Abstracts the PDU base structure into a ruby object. It gives access to its varbinds.
  #
  class PDU
    extend Forwardable 

    Error = Class.new(Error)
    class << self
      # factory method that abstracts initialization of the pdu types that the library supports.
      # 
      # @param [Symbol] type the type of pdu structure to build
      # @return [RequestPDU] a fully-formed request pdu
      # 
      def build(type, *args)
        case type
          when :get       then RequestPDU.new(Core::Constants::SNMP_MSG_GET, *args)
          when :getnext   then RequestPDU.new(Core::Constants::SNMP_MSG_GETNEXT, *args)
          when :getbulk   then RequestPDU.new(Core::Constants::SNMP_MSG_GETBULK, *args)
          when :set       then RequestPDU.new(Core::Constants::SNMP_MSG_SET, *args)
          when :response  then ResponsePDU.new(Core::Constants::SNMP_MSG_RESPONSE, *args)
          else raise Error, "#{type} is not supported as type"
        end
      end
    end

    attr_reader :struct, :varbinds

    def_delegators :@struct, :[], :[]=, :pointer

    # @param [FFI::Pointer] the pointer to the initialized structure
    #
    def initialize(pointer)
      @struct = Core::Structures::PDU.new(pointer)
      @varbinds = []
    end


  end

  # Abstracts the request PDU
  # Main characteristic is that it has a write-only API, in that you can add varbinds to it.
  #
  class RequestPDU < PDU
    def initialize(type)
      pointer = Core::LibSNMP.snmp_pdu_create(type)
      super(pointer)
    end

    # Adds a request varbind to the pdu
    # 
    # @param [OID] oid a valid oid
    # @param [Hash] options additional request varbind options
    # @option options [Object] :value the value for the oid
    def add_varbind(oid, **options)
      @varbinds << RequestVarbind.new(self, oid, options[:value], options)
    end
    alias_method :<<, :add_varbind
  end

  # Abstracts the response PDU
  # Main characteristic is: it reads the values on initialization (because the response structure
  # is at some point free'd). It is therefore a read-only entity
  #
  class ResponsePDU < PDU

    # @param [FFI::Pointer] the pointer to the response pdu structure
    #
    # @note it loads the variable as well.
    # 
    def initialize(pointer)
      super
      load_variables
    end

    # @return [String] the concatenation of the varbind values (usually, it's only one)
    # 
    def value
      case @varbinds.size
        when 0 then nil
        when 1 then @varbinds.first.value
        else 
          # assume that they're all strings
          @varbinds.map(&:value).join(' ')
      end  
    end

    private

    # loads the C-level structure variables into ruby ResponseVarbind objects, 
    # and store them as state in {{@varbinds}} 
    def load_variables
      variable = @struct[:variables]
      unless variable.null?
        @varbinds << ResponseVarbind.new(variable)
        variable = Core::Structures::VariableList.new(variable)
        while( !(variable = variable[:next_variable]).null? )
          variable = Core::Structures::VariableList.new(variable)
          @varbinds << ResponseVarbind.new(variable.pointer)
        end
      end
    end

  end
end