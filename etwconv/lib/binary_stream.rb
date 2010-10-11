require "lib/platform"
require "iconv"

class BinaryStreamException < Exception
end

class BinaryStream
  attr_reader :data
  attr_writer :ofs
  
  def initialize(data="")
    @data     = data
    @ofs      = 0
  end

  def size
    @data.size
  end
  
  def eof?
    @data.size == @ofs
  end

  ## Deal with error in formats
  ## ensure_x! do not move offset, they just raise exception or not
  def error!(msg)
    raise BinaryStreamException.new(msg)
  end
  
  def ensure_available!(bytes)
    error!("#{bytes} bytes requested but only #{@data.size-@ofs} available") if @data.size-@ofs < bytes
  end
  
  def ensure_file_size!(sz)
    error!("Expected file size #{sz} bytes, but actual is #{@data.size} bytes") unless sz == @data.size
  end

  def ensure_offset!(expected_ofs)
    error!("Expected file offset #{expected_ofs}, but actual is #{@ofs}") unless expected_ofs == @ofs
  end

  def ensure_eof!
    error!("Expected file offset #{@data.size} (EOF), but actual is #{@ofs}") unless @data.size == @ofs
  end
  
  ## Direct i/o
  def get(bytes)
    ensure_available!(bytes)
    rv, @ofs = @data[@ofs, bytes], @ofs+bytes
    rv
  end

  def put(x)
    @data << x
  end

  def <<(x)
    @data << x
  end
end

# It would be a good idea to move as much as possible into these subclasses,
# and achieve more reader/writer symetry 

class BinaryStreamWriter < BinaryStream
  def initialize
    super("")
  end
  def packed(fmt, data)
    @data << data.pack(fmt)
  end
  def magic(magic)
    @data << magic
  end
  def u4_ary(items, &blk)
    u4 items.size
    items.each(&blk)
  end
  def u2_ary(items, &blk)
    u2 items.size
    items.each(&blk)
  end
  def esf_nodenames(nn)
    u2_ary(nn){|n| ascii(n)}
  end
  FmtNames.each{|name,fmt| 
     eval %Q[def #{name}(arg); @data << [arg].pack(#{fmt.inspect}); end]
  }
  def ascii(s)
    u2(s.size)
    put(s)
  end
  def str(s)
    s = Iconv.conv("UTF-16LE", "UTF-8", s)
    u2(s.size/2)
    put(s)
  end
  def self.open
    s = new
    yield(s)
    s.data
  end
end

class BinaryStreamReader < BinaryStream
  def u4_ary(&blk)
    (0...u4).map(&blk)
  end
  def u2_ary(&blk)
    (0...u2).map(&blk)
  end
  def esf_nodenames
    u2_ary{ ascii }
  end
  def ascii
    get(u2)
  end
  def packed(fmt)
    get(FmtSizes[fmt]).unpack(fmt)
  end
  def magic(magic)
    actual = get(magic.size)
    unless actual == magic
      raise BinaryStreamException.new("Magic expected %s but got %s" % [magic.unpack("H2"*magic.size).join(" "), actual.unpack("H2"*actual.size).join(" ")])
    end
    nil
  end
  def str
    Iconv.conv("UTF-8", "UTF-16LE", get(u2*2))
  end
  FmtNames.each{|name,fmt| 
     eval %Q[def #{name}; get(#{FmtSizes[fmt]}).unpack(#{fmt.inspect})[0]; end]
  }
  def self.open(data)
    s = new(data)
    res = yield(s)
    s.ensure_eof!
    res
  end
end
