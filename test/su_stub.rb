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

  # Rigid transformation: rotation (columns x, y, z) + translation.
  class Transformation
    attr_reader :r, :t

    def initialize(t = [0, 0, 0], r = nil)
      t = t.to_a if t.is_a?(Point3d) || t.is_a?(Vector3d)
      @t = t.map(&:to_f)
      @r = r || [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]] # columns
    end

    def self.axes(o, x, y, z)
      new(o.to_a, [x.to_a, y.to_a, z.to_a].map { |c| c.map(&:to_f) })
    end

    def rot(v)
      [0, 1, 2].map { |i| @r[0][i] * v[0] + @r[1][i] * v[1] + @r[2][i] * v[2] }
    end

    def apply(p)
      q = rot(p.to_a)
      Point3d.new(q[0] + t[0], q[1] + t[1], q[2] + t[2])
    end

    def apply_vec(v)
      Vector3d.new(*rot(v.to_a))
    end

    def *(other)
      cols = other.r.map { |c| rot(c) }
      tt = rot(other.t)
      Transformation.new([tt[0] + t[0], tt[1] + t[1], tt[2] + t[2]], cols)
    end

    def self.scaling(kx, ky = kx, kz = kx)
      new([0, 0, 0], [[kx.to_f, 0.0, 0.0], [0.0, ky.to_f, 0.0], [0.0, 0.0, kz.to_f]])
    end

    def self.translation(v)
      new(v.to_a)
    end

    # General 3×3 inverse (supports scaling), m[row][col] = @r[col][row].
    def inverse
      m = [0, 1, 2].map { |i| [0, 1, 2].map { |j| @r[j][i] } }
      det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
            m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
            m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
      inv = [[(m[1][1] * m[2][2] - m[1][2] * m[2][1]), -(m[0][1] * m[2][2] - m[0][2] * m[2][1]), (m[0][1] * m[1][2] - m[0][2] * m[1][1])],
             [-(m[1][0] * m[2][2] - m[1][2] * m[2][0]), (m[0][0] * m[2][2] - m[0][2] * m[2][0]), -(m[0][0] * m[1][2] - m[0][2] * m[1][0])],
             [(m[1][0] * m[2][1] - m[1][1] * m[2][0]), -(m[0][0] * m[2][1] - m[0][1] * m[2][0]), (m[0][0] * m[1][1] - m[0][1] * m[1][0])]]
      inv = inv.map { |row| row.map { |x| x / det } }
      cols = [0, 1, 2].map { |j| [0, 1, 2].map { |i| inv[i][j] } }
      tmp = Transformation.new([0, 0, 0], cols)
      Transformation.new(tmp.rot(t).map(&:-@), cols)
    end
  end

  class PolygonMesh
    attr_reader :polygons

    def initialize(*_a)
      @polygons = []
    end

    def add_polygon(*pts)
      @polygons << pts.flatten
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

    def delete_attribute(d, k)
      dicts[d]&.delete(k)
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
    attr_accessor :back_material, :pins

    def position_material(mat, pins, _front)
      self.material = mat
      @pins = pins
      true
    end

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

    def add_faces_from_mesh(mesh, _flags = 0, mat = nil, _back = nil)
      $mesh_polys = ($mesh_polys || 0) + mesh.polygons.size
      blob = self << MeshBlob.new(mesh.polygons.size)
      blob.material = mat
      self << Face.new unless mesh.polygons.empty?
      mesh.polygons.size
    end

    def add_instance(defn, tr)
      inst = ComponentInstance.new(defn, tr)
      defn.instances << inst
      self << inst
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
    include Attributable
    attr_reader :entities, :instances, :name
    attr_accessor :description

    def initialize(inst = nil, name = nil)
      @entities = Entities.new(self)
      @instances = inst ? [inst] : []
      @name = name
    end

    def count_instances
      @instances.count(&:valid?)
    end

    def save_as(path)
      File.write(path, "stub skp #{@name}")
      true
    end
  end

  class DefinitionList
    include Enumerable

    def initialize
      @h = {}
    end

    def [](n)
      @h[n]
    end

    def add(n)
      @h[n] = Definition.new(nil, n)
    end

    def each(&block)
      @h.values.each(&block)
    end

    def remove(d)
      @h.delete(d.name)
    end

    def load(path)
      @h[path] ||= Definition.new(nil, File.basename(path, '.skp'))
    end
  end

  class MeshBlob < Entity
    attr_reader :count

    def initialize(n)
      super()
      @count = n
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

  class ComponentInstance < Group
    def initialize(defn = nil, tr = nil)
      super()
      @definition = defn if defn
      @transformation = tr if tr
    end
  end

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
    attr_reader :rgb

    def initialize(*rgb)
      @rgb = rgb
    end
  end

  class Material
    include Attributable
    attr_accessor :color, :alpha, :name, :texture

    def initialize(n)
      @name = n
    end
  end

  class Materials
    include Enumerable

    def initialize
      @h = {}
    end

    def each(&block)
      @h.values.each(&block)
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

    attr_accessor :ray_hits

    def definitions
      @definitions ||= DefinitionList.new
    end

    def rendering_options
      @rendering_options ||= {}
    end

    # ray_hits: lambda(point_mm_array, dir_array) → [hit_point_mm, path] or nil
    def raytest(ray, _wysiwyg = true)
      return nil unless @ray_hits

      pt, vec = ray
      hit = @ray_hits.call(pt.to_a.map { |c| c * 25.4 }, vec.to_a)
      hit && [Geom::Point3d.new(*hit[0].map { |c| c / 25.4 }), hit[1] || []]
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
      attr_accessor :next_position, :next_vertex, :next_dof
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
      return InputPoint.next_dof if InputPoint.next_dof

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
    attr_reader :tool

    def active_view
      @active_view ||= View.new
    end

    def select_tool(tool)
      @tool = tool
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
