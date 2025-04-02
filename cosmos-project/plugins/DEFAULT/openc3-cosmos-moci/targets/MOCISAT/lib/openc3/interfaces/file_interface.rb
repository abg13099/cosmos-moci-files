require 'openc3/interfaces/interface'
require 'openc3/config/config_parser'
require 'thread'
require 'listen'
require 'fileutils'

module OpenC3
  class FileInterface < Interface
    def initalize(
      telemetry_read_folder,
      telemetry_archive_folder
      file_read_size = 65536,
      stored = true,
      protocol_type = nil,
      *protocol_args
    )
      super()
      @protocol_type = ConfigParser.handle_nil(protocol_type)
      @protocol_args = protocol_args
      if @protocol_type
        protocol_class_name = protocol_type.to_s.capitalize << 'Protocol'
        klass = OpenC3.require_class(protocol_class_name.class_name_to_filename)
        add_protocol(klass, protocol_args, :PARAMS)
      end
      @telemetry_read_folder = ConfigParser.handle_nil(telemetry_read_folder)
      @telemetry_archive_folder = ConfigParser.handle_nil(telemetry_archive_folder)
      @file_read_size = Integer(file_read_size)
      @stored = ConfigParser.handle_true_false(stored)

      @read_allowed false unless @telemetry_read_folder
      
      @file = nil
      @listener = nil
      @connected = false
    end

    def connect
      super()

      if @telemetry_read_folder
        @listener = Listen.to(@telemetry_read_folder, force_polling: @polling) do |modified, added, removed|
          @queue << added if needed
        end
        @listener.start
      end
      @connected = true
    end

    def connected?
      return @connected
    end

    def disconnect
      @file.close if @file and not @file.closed
      @file = nil
      @listener.stop if @listener
      @listener = nil
      @queue << nil
      super()
      @connected = false
    end
  
    def read_interface
      while true
        if @file
          #if there is new data in the file parse it
          data = @file.read(@file_read_size)
          if data and data.length > 0
            read_interface_base(data, nil)
          else
            finish_file()
          end
        end

        #find next file
        file = get_next_telemetry_file()
        if file
          @file = File.open(file, 'rb')
          next
        end

        #wait for a file to read
        result = @queue.pop
        return nil, nil unless result
      end
    end

    def write_interface
      return nil
    end

    def convert_data_to_packet(data, extra = nil)
      packet = super(data, extra)
      if packet and @stored
        packet.stored = true
      end
      return packet
    end
    
    def finish_file
      path = @file.path
      @file.close
      @file = nil

      # Archive (or DELETE) complete file
      if @telemetry_archive_folder == "DELETE"
        FileUtils.rm(path)
      else
        FileUtils.mv(path, @telemetry_archive_folder)
      end
    end

    def get_next_telemetry_file
      if @recursive
        return Dir.glob("#{@telemetry_read_folder}/**/*").sort[0]
      else
        return Dir.glob("#{@telemetry_read_folder}/*").sort[0]
      end
    end
  end
end
