require "time"

require "rubygems"
require "maruku"

class FileModel
  attr_reader :filename, :mtime
  
  @@cache = {}
  
  def self.model_path(basename = nil)
    Nesta::Configuration.content_path(basename)
  end
  
  def self.find_all
    file_pattern = File.join(model_path, "**", "*.mdown")
    Dir.glob(file_pattern).map do |path|
      load(path.sub(model_path + "/", "").sub(".mdown", ""))
    end
  end
  
  def self.needs_loading?(path, filename)
    @@cache[path].nil? || File.mtime(filename) > @@cache[path].mtime
  end
  
  def self.load(path)
    filename = model_path("#{path}.mdown")
    if File.exist?(filename) && needs_loading?(path, filename)
      @@cache[path] = self.new(filename)
    end
    @@cache[path]
  end
  
  def self.purge_cache
    @@cache = {}
  end
  
  def initialize(filename)
    @filename = filename
    parse_file
    @mtime = File.mtime(filename)
  end

  def permalink
    File.basename(@filename, ".*")
  end

  def path
    abspath.sub(/^\//, "")
  end
  
  def abspath
    prefix = File.dirname(@filename).sub(Nesta::Configuration.page_path, "")
    File.join(prefix, permalink)
  end
  
  def to_html
    Maruku.new(markup).to_html
  end
  
  def last_modified
    @last_modified ||= File.stat(@filename).mtime
  end
  
  def description
    metadata("description")
  end
  
  def keywords
    metadata("keywords")
  end

  private
    def markup
      @markup
    end
    
    def metadata(key)
      @metadata[key]
    end
    
    def paragraph_is_metadata(text)
      text.split("\n").first =~ /^[\w ]+:/
    end
    
    def parse_file
      first_para, remaining = File.open(@filename).read.split(/\r?\n\r?\n/, 2)
      @metadata = {}
      if paragraph_is_metadata(first_para)
        @markup = remaining
        for line in first_para.split("\n") do
          key, value = line.split(/\s*:\s*/, 2)
          @metadata[key.downcase] = value.chomp
        end
      else
        @markup = [first_para, remaining].join("\n\n")
      end
    rescue Errno::ENOENT  # file not found
      raise Sinatra::NotFound
    end
end

class Page < FileModel
  module ClassMethods
    def model_path(basename = nil)
      Nesta::Configuration.page_path(basename)
    end
    
    def find_by_path(path)
      load(path)
    end

    def find_articles
      find_all.select { |page| page.date }.sort { |x, y| y.date <=> x.date }
    end
    
    def menu_items
      menu = Nesta::Configuration.content_path("menu.txt")
      pages = []
      if File.exist?(menu)
        File.open(menu).each { |line| pages << Page.load(line.chomp) }
      end
      pages
    end
  end

  extend ClassMethods
  
  def ==(other)
    self.path == other.path
  end
  
  def heading
    markup =~ /^#\s*(.*)/
    Regexp.last_match(1)
  end
  
  def date(format = nil)
    @date ||= if metadata("date")
      if format == :xmlschema
        Time.parse(metadata("date")).xmlschema
      else
        DateTime.parse(metadata("date"))
      end
    end
  end
  
  def atom_id
    metadata("atom id")
  end
  
  def read_more
    metadata("read more") || "Continue reading"
  end
  
  def summary
    metadata("summary") && metadata("summary").gsub('\n', "\n")
  end
  
  def sidebar
    filename = "#{self.class.model_path(path)}.sidebar"
    File.exist?(filename) ? File.open(filename).read : nil 
  end
  
  def body
    Maruku.new(markup.sub(/^#\s.*$\r?\n(\r?\n)?/, "")).to_html
  end
  
  def categories
    categories = metadata("categories")
    paths = if categories.nil?
      []
    else
      categories.split(",").map { |p| p.strip }
    end
    paths = paths.select do |path|
      filename = File.join(Nesta::Configuration.page_path, "#{path}.mdown")
      File.exist?(filename)
    end
    paths.map { |p| Page.find_by_path(p) }.sort do |x, y|
      x.heading.downcase <=> y.heading.downcase
    end
  end
  
  def parent
    Page.load(File.dirname(path))
  end
  
  def pages
    Page.find_all.select do |page|
      page.date.nil? && page.categories.include?(self)
    end.sort { |x, y| x.heading.downcase <=> y.heading.downcase }
  end
  
  def articles
    Page.find_articles.select { |article| article.categories.include?(self) }
  end
end
