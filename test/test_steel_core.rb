# frozen_string_literal: true

require_relative 'steel_helper'

# Steel Supports TH core: real section sizes, hardware, statics and the
# four details of the user's drawings.
class TestSteelCore < Minitest::Test
  P = SteelSU.method(:pipe)

  def closed(res, label)
    res.part.solids.each_with_index do |(role, s), i|
      assert SS::Mesh.closed?(s), "#{label}: solid #{i} (#{role}) not closed"
      assert SS::Mesh.volume(s).positive?, "#{label}: solid #{i} (#{role}) inside out"
    end
  end

  def zs(res, role = :steel)
    res.part.solids.select { |r, _| r == role }.flat_map { |_, s| s.polys.flatten(1).map { |p| p[2] } }
  end

  def ys(res, role = :steel)
    res.part.solids.select { |r, _| r == role }.flat_map { |_, s| s.polys.flatten(1).map { |p| p[1] } }
  end

  # The drawing: cold water, chilled water + insulation, air; steam on top.
  def drawing
    [P.call(0, 0, 60.3, 0, '2" CW'), P.call(200, 70, 88.9, 50, '3" CHWS'), P.call(390, -15, 33.4, 0, '1" CA'),
     P.call(180, 420, 60.3, 50, '2" STM')]
  end

  def test_section_outlines_weigh_what_the_tables_say
    SS::Steel::SECTIONS.each_key do |k|
      geo = SS::Mesh.area2d(SS::Steel.profile(k)) * SS::Steel::RHO * 1000.0
      assert_in_delta SS::Steel.kg_m(k), geo, 0.01 * SS::Steel.kg_m(k), "#{k}: #{geo.round(2)} kg/m"
    end
    # cold-formed and angle properties straight from the outline match the tables
    lc = SS::Steel.props('LC100T')
    assert_in_delta 107.0e4, lc[:i_edge], 0.02 * 107.0e4 # JIS G 3350 C100×50×20×3.2: Ix 107 cm⁴
    assert_in_delta 24.5e4, lc[:i_flat], 0.02 * 24.5e4   # Iy 24.5 cm⁴
    l50 = SS::Steel.props('L50')
    assert_in_delta 11.1e4, l50[:i_flat], 0.02 * 11.1e4  # L50×50×5: 11.1 cm⁴
    assert_in_delta 7.52e3, SS::Steel.props('C100')[:z_flat], 1.0 # rolled (tapered) channel: JIS table
  end

  def test_members_are_closed_and_in_place
    s = SS::Steel.member('C100', [0, 0, 0], [0, 1000, 0], [1, 0, 0], [0, 0, -1])
    assert SS::Mesh.closed?(s)
    pts = s.polys.flatten(1)
    assert_in_delta(-50.0, pts.map { |p| p[2] }.min, 1e-6) # toes 50 below the web back
    assert_in_delta 0.0, pts.map { |p| p[2] }.max, 1e-6
    assert_in_delta 50.0, pts.map { |p| p[0] }.max, 1e-6 # depth 100 centred
    sloped = SS::Steel.member('C75', [0, 0, 0], [0, 300, 300], [1, 0, 0], [0, -0.7071, 0.7071],
                              cut0: [[0, 0, 0], [0, 1, 0]], cut1: [[0, 300, 300], [0, 0, 1]])
    assert SS::Mesh.closed?(sloped)
    assert_operator SS::Mesh.volume(sloped), :>, 0
  end

  def test_hardware_sizes
    assert_equal '3/8', SS::Hardware.u_bolt_size(60.3)
    assert_equal '1/2', SS::Hardware.u_bolt_size(114.3)
    assert_equal '5/8', SS::Hardware.u_bolt_size(219.1)
    assert_equal '1/2', SS::Hardware.size_for(3.0, :rod_kn)  # > 2.71 kN of 3/8"
    part = SS::Mesh::Part.new
    SS::Hardware.u_bolt(part, [0, 0, 0], [0, 1, 0], [0, 0, 1], 30.0, '3/8', 60.0)
    SS::Hardware.anchor(part, [0, 0, 0], [0, 1, 0], 5.0, '1/2')
    part.solids.each { |_, s| assert SS::Mesh.closed?(s) }
  end

  def test_beam_formulas
    ei = SS::Steel::E * 1.0e6
    r = SS::Beam.two_support(0, 1000, 0, 1000, [[500, 1000.0]], ei)
    assert_in_delta 250_000.0, r[:m_max], 1.0        # PL/4
    assert_in_delta 1000.0 * 1000**3 / (48 * ei), r[:defl], 0.02 * 1000.0 * 1000**3 / (48 * ei)
    r = SS::Beam.two_support(0, 1500, 0, 1000, [[1500, 100.0]], ei) # overhang
    assert_in_delta 50_000.0, r[:m_max], 1.0
    assert_in_delta(-50.0, r[:r1], 1e-6)
    assert_in_delta 150.0, r[:r2], 1e-6
  end

  def test_wall_frame_like_the_drawing
    res = SS::Details.wall_frame(drawing, 420)
    closed(res, 'wf')
    assert_equal 'C100', res.info[:section], 'C 4" as drawn (light loads)'
    assert_equal '1/2', res.info[:anchor]
    assert_equal 3, res.info[:anchors]
    assert_equal 4, res.carried.size, 'three inside, steam on top'
    assert res.ok?
    # back post web on the wall face, bottom member web under the lowest pipe
    assert_in_delta(-420.0, ys(res).min, 1e-6)
    assert_in_delta(-31.7 - 50.0, zs(res).min, 1e-6) # the 1" air line is the lowest
    # the angle shoe reaches the bare steam pipe
    assert_in_delta 420 - 30.15, zs(res).max, 1e-6
    assert_equal 3, res.bom.find { |b| b[:cat] == 'anchor' }[:qty]
    assert_equal 3, res.bom.count { |b| b[:cat] == 'ubolt' }
  end

  def test_wall_frame_leaves_out_pipes_it_cannot_take
    # 8": the next one is 304 above its underside – no packer that tall, and
    # too low to clear the top member; one against the wall, one too far
    pipes = [P.call(0, 0, 219.1), P.call(300, 250.15, 60.3), P.call(-520, 0, 60.3), P.call(1300, 0, 60.3)]
    res = SS::Details.wall_frame(pipes, 600)
    assert_equal 1, res.carried.size
    assert_equal 3, res.notes.size # between the levels, against the wall, too far
  end

  def test_wall_bracket_like_the_drawing
    res = SS::Details.wall_bracket(drawing.first(2), 300)
    closed(res, 'wb')
    assert_equal 'C75', res.info[:section]
    assert_equal '3/8', res.info[:anchor]
    assert res.ok?
    # arm web under the lowest pipe, the other on a packer, post on the wall
    assert_in_delta(70 - 94.45, zs(res).max, 1e-6)
    assert_in_delta(-300.0, ys(res).min, 1e-6)
    names = res.checks.map { |c| c[:item] }
    assert(names.any? { |n| n.include?('ค้ำยัน') })
  end

  def test_heavier_load_takes_bigger_steel_and_anchors
    heavy = [P.call(0, 0, 219.1, 0, '8"'), P.call(400, 0, 219.1, 0, '8"'), P.call(800, 0, 168.3, 0, '6"')]
    res = SS::Details.wall_bracket(heavy, 400, spacing_m: 4.0)
    assert res.ok?
    refute_equal 'C75', res.info[:section]
    refute_equal '3/8', res.info[:anchor]
    over = SS::Details.wall_bracket(heavy, 400, spacing_m: 6.0)
    assert over.members_ok?, 'steel still sized'
    refute over.ok?
    assert(over.notes.any? { |n| n.include?('พุกรับแรงไม่พอ') })
    fixed = SS::Details.wall_bracket(heavy, 200, spacing_m: 6.0, section: 'C75', anchor: '3/8')
    refute fixed.ok?, 'a fixed small section is reported as failing'
  end

  def test_truss_hang_like_the_drawing
    chord = { kind: :round, z: 900.0, r: 24.15 }
    res = SS::Details.truss_hang(drawing.first(2), chord)
    closed(res, 'th')
    assert_equal '3/8', res.info[:rod]
    assert res.ok?
    # cleat toes touch the chord underside; U-bolt over the chord top
    assert_in_delta 900 - 24.15, zs(res).max, 1e-6
    assert_operator zs(res, :galv).max, :>, 900 + 24.15
    assert_equal 2, res.bom.count { |b| b[:desc].include?('รัด truss') }
    heavy = SS::Details.truss_hang([P.call(0, 0, 219.1), P.call(300, 0, 219.1)], chord, spacing_m: 6.0)
    assert_equal '1/2', heavy.info[:rod], 'rod sized for the load (MSS SP-58)'
    flat = SS::Details.truss_hang(drawing.first(2), { kind: :flat, z: 900.0 })
    closed(flat, 'th flat')
    assert(flat.bom.any? { |b| b[:desc].include?('Drop-in') })
  end

  def test_truss_top_like_the_drawing
    chords = [{ y: -150.0, z: -100.0, r: 24.15 }, { y: 420.0, z: -100.0, r: 24.15 }]
    pipes = [P.call(0, 0, 60.3), P.call(200, 14.3, 88.9)] # undersides level at −30.15
    res = SS::Details.truss_top(pipes, chords)
    closed(res, 'tt')
    assert res.ok?
    assert_equal 2, res.info[:chords]
    # channel toes on the chord tops, web top under the pipes (packers fill the rest)
    assert_in_delta(-100 + 24.15, zs(res).min, 1e-6)
    err = assert_raises(RuntimeError) { SS::Details.truss_top([P.call(0, -60, 60.3)], chords) }
    assert_match(/ต่ำกว่า/, err.message)
    one = SS::Details.truss_top(pipes, chords.first(1))
    assert(one.notes.any? { |n| n.include?('เส้นเดียว') })
  end

  def test_grouping_and_cylinder_fit
    list = [P.call(0, 0, 60.3), P.call(250, 0, 60.3), P.call(1200, 0, 60.3), P.call(-200, 400, 60.3)]
    assert_equal [0.0, 250.0], SS::Pipes.group(list).map { |p| p[:y] }
    assert_equal 3, SS::Pipes.group(list, rise: 1200.0, below: 1200.0).size
    # a 24-facet tube along (1, 1, 0) of radius 57
    ax = SS::Vec.unit([1, 1, 0])
    u = SS::Vec.perpendicular(ax)
    v = SS::Vec.cross(ax, u)
    normals = []
    pts = []
    24.times do |k|
      t = 2 * Math::PI * (k + 0.5) / 24
      normals << SS::Vec.add(SS::Vec.scale(u, Math.cos(t)), SS::Vec.scale(v, Math.sin(t)))
      t2 = 2 * Math::PI * k / 24
      c = SS::Vec.add([100, 200, 300], SS::Vec.add(SS::Vec.scale(u, 57 * Math.cos(t2)), SS::Vec.scale(v, 57 * Math.sin(t2))))
      pts << c << SS::Vec.along(c, ax, 2000)
    end
    cyl = SS::Pipes.fit_cylinder(normals, pts)
    assert_in_delta 57.0, cyl[:radius], 0.01
    assert_in_delta 1.0, SS::Vec.dot(cyl[:axis], ax).abs, 1e-9
    assert_in_delta 2000.0, cyl[:length], 1e-6
    assert_nil SS::Pipes.fit_cylinder([[0, 0, 1], [0, 1, 0], [1, 0, 0]], pts), 'a box is no pipe'
  end
end
