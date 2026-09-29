# frozen_string_literal: true

# Minimal stand-in for the SketchUp Ruby API – just enough to execute the
# extension's SketchUp layer (builder, collector, picker, valves, commands)
# in plain Ruby. Geometry calls are recorded, not modelled.

module Geom
  class Point3d
    attr_reader :x, :y, :z

    def initialize(x = 0, y = 0, z = 0)
      x, y, z = x.to_a if x.is_a?(Point3d) || x.is_a?(Array)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def to_a
      [x, y, z]
    end

    def transform(tr)
      tr.apply(self)
    end

    def -(other)
      Vector3d.new(x - other.x, y - other.y, z - other.z)
    end
  end

  class Vector3d
    attr_reader :x, :y, :z

    def initialize(x = 0, y = 0, z = 0)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def to_a
      [x, y, z]
    end

    def dot(o)
      x * o.x + y * o.y + z * o.z
    end

    def length
      Math.sqrt(dot(self))
    end

    def transform(tr)
      tr.apply_vec(self)
    end

    def angle_between(o)
      Math.acos([[dot(o) / (length * o.length), 1.0].min, -1.0].max)
    end
  end

  # Translation-only transformation (sufficient for the tests).
  class Transformation
    attr_reader :t

    def initialize(t = [0, 0, 0])
      t = t.to_a if t.is_a?(Point3d) || t.is_a?(Vector3d)
      @t = t.map(&:to_f)
    end

    def apply(p)
      Point3d.new(p.x + t[0], p.y + t[1], p.z + t[2])
    end

    def apply_vec(v)
      Vector3d.new(v.x, v.y, v.z)
    end

    def *(other)
      Transformation.new([t[0] + other.t[0], t[1] + other.t[1], t[2] + other.t[2]])
    end

    def inverse
      Transformation.new(t.map(&:-@))
    end
  end

  class BoundingBox
    def add(*_a)
      self
    end
  end
end

module Sketchup
  @defaults = {}
  class << self
    attr_accessor :active_model, :status_text, :vcb_label, :vcb_value

    def read_default(sec, key, default = nil)
      @defaults.fetch([sec, key], default)
    end

    def write_default(sec, key, val)
      @defaults[[sec, key]] = val
    end

    def platform
      :platform_win
    end

    def format_length(l)
      "#{(l * 25.4).round}mm"
    end
  end

  class AttrDict < Hash
    def each_pair(&block)
      each(&block)
    end
  end

  module Attributable
    def dicts
      @dicts ||= {}
    end

    def set_attribute(d, k, v)
      (dicts[d] ||= AttrDict.new)[k] = v
    end

    def get_attribute(d, k, default = nil)
      (dicts[d] || {}).fetch(k, default)
    end

    def attribute_dictionary(d)
      dicts[d]
    end
  end

  class Entity
    include Attributable
    attr_accessor :layer, :material, :name, :parent

    def valid?
      !@erased
    end

    def erase!
      @erased = true
    end
  end

  class Vertex
    attr_reader :position

    def initialize(p)
      @position = p
    end
  end

  class Edge < Entity
    attr_accessor :soft, :smooth
    attr_reader :start, :end

    def initialize(a, b)
      super()
      @start = Vertex.new(a)
      @end = Vertex.new(b)
    end

    def faces
      []
    end
  end

  class Face < Entity
    def followme(path)
      $followme_calls = ($followme_calls || 0) + 1
      !path.empty?
    end

    def normal
      Geom::Vector3d.new(0, 0, -1)
    end

    def reverse!; end

    def orient_connected_faces; end
  end

  class Text < Entity; end
  class ConstructionPoint < Entity; end

  class Entities
    include Enumerable
    attr_reader :parent

    def initialize(parent = nil)
      @list = []
      @parent = parent
    end

    def each(&block)
      @list.select(&:valid?).each(&block)
    end

    def <<(e)
      e.parent = self
      @list << e
      e
    end

    def add_group
      self << Group.new
    end

    def add_line(a, b)
      return nil if (a - b).length < 1e-6

      self << Edge.new(a, b)
    end

    def add_arc(_c, _x, _n, _r, _a0, _a1, segs)
      Array.new(segs) { self << Edge.new(Geom::Point3d.new, Geom::Point3d.new(1, 0, 0)) }
    end

    def add_circle(_c, _n, r, segs)
      raise ArgumentError, 'radius' unless r.positive?

      Array.new(segs) { self << Edge.new(Geom::Point3d.new, Geom::Point3d.new(1, 0, 0)) }
    end

    def add_face(_edges)
      self << Face.new
    end

    def add_text(_s, _p, _v = nil)
      self << Text.new
    end

    def add_cpoint(_p)
      self << ConstructionPoint.new
    end

    def clear!
      @list.each(&:erase!)
      @list = []
    end

    def erase_entities(ents)
      Array(ents).each(&:erase!)
    end
  end

  class Definition
    attr_reader :entities, :instances

    def initialize(inst)
      @entities = Entities.new(self)
      @instances = [inst]
    end
  end

  class Group < Entity
    attr_accessor :transformation

    @@pid = 0

    def initialize
      super
      @definition = Definition.new(self)
      @transformation = Geom::Transformation.new
      @@pid += 1
      @pid = @@pid
    end

    attr_reader :definition

    def entities
      @definition.entities
    end

    def persistent_id
      @pid
    end

    def transform!(tr)
      @transformation = tr * @transformation
    end
  end

  class ComponentInstance < Group; end

  class Layer
    attr_reader :name

    def initialize(n)
      @name = n
    end
  end

  class Layers
    def initialize
      @h = {}
    end

    def [](n)
      @h[n]
    end

    def add(n)
      @h[n] ||= Layer.new(n)
    end
  end

  class Color
    def initialize(*rgb)
      @rgb = rgb
    end
  end

  class Material
    attr_accessor :color, :alpha, :name

    def initialize(n)
      @name = n
    end
  end

  class Materials
    def initialize
      @h = {}
    end

    def [](n)
      @h[n]
    end

    def add(n)
      @h[n] ||= Material.new(n)
    end
  end

  class Selection < Array; end

  class Model
    include Attributable
    attr_reader :entities, :layers, :materials, :selection, :ops
    attr_accessor :active_path

    def initialize
      @entities = Entities.new(self)
      @layers = Layers.new
      @materials = Materials.new
      @selection = Selection.new
      @ops = []
    end

    def active_entities
      @entities
    end

    def edit_transform
      Geom::Transformation.new
    end

    def title
      'Test'
    end

    def start_operation(name, *_a)
      @ops << [:start, name]
    end

    def commit_operation
      @ops << [:commit]
    end

    def abort_operation
      @ops << [:abort]
    end
  end
end

module UI
  @messages = []
  class << self
    attr_reader :messages

    def messagebox(msg, *_a)
      @messages << msg
      6 # IDYES
    end

    def beep; end
  end
end

MB_YESNO = 4
MB_OKCANCEL = 1
IDYES = 6
IDOK = 1

class Numeric
  def mm
    self / 25.4
  end
end

module UI
  class << self
    attr_accessor :inputbox_answer, :last_html

    def inputbox(*_a)
      inputbox_answer
    end

    def savepanel(*_a)
      nil
    end
  end

  class HtmlDialog
    STYLE_DIALOG = 0
    STYLE_UTILITY = 1

    def initialize(_opts = {}); end

    def set_html(h)
      UI.last_html = h
    end

    def add_action_callback(*_a); end

    def show; end
  end
end

module Sketchup
  # InputPoint whose pick position is set by the test.
  class InputPoint
    class << self
      attr_accessor :next_position, :next_vertex
    end
    attr_reader :position

    def initialize(p = nil)
      @position = p
    end

    def pick(_view, _x, _y, _anchor = nil)
      @position = InputPoint.next_position
      true
    end

    def valid?
      !@position.nil?
    end

    def clear
      @position = nil
    end

    def vertex
      InputPoint.next_vertex
    end

    def degrees_of_freedom
      InputPoint.next_vertex ? 0 : 3
    end

    def face; end

    def edge; end

    def tooltip
      ''
    end

    def display?
      false
    end
  end

  class View
    attr_accessor :tooltip

    def invalidate; end
  end

  class Model
    def active_view
      @active_view ||= View.new
    end
  end
end

VK_RIGHT = 39
VK_LEFT = 37
VK_UP = 38
VK_DOWN = 40
CONSTRAIN_MODIFIER_KEY = 16

class String
  # SketchUp parses lengths in model units; the tests use millimetres.
  def to_l
    Float(self) / 25.4
  end
end
