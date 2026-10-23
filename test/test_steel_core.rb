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

# The user's standard column supports A–D: steel exactly as drawn.
class TestSteelStd < Minitest::Test
  P = SteelSU.method(:pipe)

  def steel(res)
    res.part.solids.select { |r, _| r == :steel }.flat_map { |_, s| s.polys.flatten(1) }
  end

  def range(pts, i)
    pts.map { |p| p[i] }.minmax.map { |v| v.round(3) }
  end

  def test_all_closed_and_sized_as_drawn
    { 'A' => [[0, 310], [-300, 0], [-20, 20]], 'B' => [[0, 480], [-400, 0], [-25, 25]],
      'D' => [[0, 870], [-100, 420], [-100, 100]] }.each do |t, (ys, zs, xs)| # D: the steam's shoe 0.20 long
      res = SS::Std.build(t)
      res.part.solids.each { |role, s| assert SS::Mesh.closed?(s), "#{t} #{role}" }
      res.part.solids.each { |_, s| assert_operator SS::Mesh.volume(s), :>, 0 }
      pts = steel(res)
      assert_equal ys, range(pts, 1), "#{t} out from the column face"
      assert_equal zs, range(pts, 2), "#{t} height"
      assert_equal xs, range(pts, 0), "#{t} flange width along the pipe"
    end
    c = SS::Std.build('C')
    assert_equal [0.0, 870.0], range(steel(c), 1)
    assert_equal [-100.0, 420.0], range(steel(c), 2), 'the frame (steam on a shoe inside since 2.3)'
  end

  def test_sections_anchors_and_bom_as_drawn
    a = SS::Std.build('A')
    assert_equal 'C75', a.info[:section]
    assert_equal '3/8', a.info[:anchor]
    assert_equal 2, a.bom.find { |b| b[:cat] == 'anchor' }[:qty]
    assert_equal [310, 300, 318], a.bom.select { |b| b[:cat] == 'steel' }.map { |b| b[:length] }
    b = SS::Std.build('B')
    assert_equal 'C100', b.info[:section]
    assert_equal '3/8', b.info[:anchor]
    assert_equal [480, 400, 424], b.bom.select { |r| r[:cat] == 'steel' }.map { |r| r[:length] }
    %w[C D].each do |t|
      r = SS::Std.build(t)
      assert_equal '1/2', r.info[:anchor]
      assert_equal 3, r.bom.find { |x| x[:cat] == 'anchor' }[:qty]
      assert_equal [1740, 1040], r.bom.select { |x| x[:cat] == 'steel' && x[:key] == 'C100' }.map { |x| x[:length] }
    end
    c = SS::Std.build('C')
    assert_equal %w[L50 L50], c.bom.select { |x| x[:cat] == 'steel' && x[:key] != 'C100' }.map { |x| x[:key] }, 'shoe guides'
  end

  def test_drawing_pipe_positions_when_no_pipes
    d = SS::Std.build('D')
    assert d.info[:nominal]
    assert_equal [290.0, 500.0, 650.0], d.carried.map { |p| p[:y] }.sort # 0.19 in, 0.50, 0.12 in from the front
    assert_equal 3, d.info[:guides].size
  end

  def test_u_bolts_follow_the_pipes_steel_stays
    pipes = [P.call(300, 84.15, 168.3, 0, '6"'), P.call(520, 30.15 + 40, 60.3, 0, '2"')] # 2" on a 40 packer
    d = SS::Std.build('D', pipes)
    refute d.info[:nominal]
    assert_equal [300.0, 520.0], d.carried.map { |p| p[:y] }
    assert_equal [0, 870], [steel(d).map { |p| p[1] }.min.round, steel(d).map { |p| p[1] }.max.round]
    assert(d.bom.any? { |b| b[:cat] == 'plate' }, 'packer under the higher pipe')
    # the 6" U-bolt straddles y = 300 (not the drawing's 330)
    ub = d.part.solids.map { |_, s| s.polys.flatten(1) }.find do |pts|
      ys = pts.map { |p| p[1] }
      pts.map { |p| p[2] }.max > 160 && ys.min > 150 && ys.max < 450
    end
    ys = ub.map { |p| p[1] }
    assert_in_delta 300.0, (ys.min + ys.max) / 2.0, 1e-6
    assert_in_delta 2 * (84.15 + 1 + 12.7), ys.max - ys.min, 1e-6
    out = SS::Std.build('A', [P.call(0, 30, 60.3, 0, 'x'), P.call(165, 57.15, 114.3, 0, '4"')])
    assert_equal ['4"'], out.carried.map { |p| p[:label] }
    assert(out.notes.any? { |n| n.include?('x') }, 'the pipe against the column is noted')
  end

  # Up to 6" on every type, wherever it fits in the steel as drawn.
  def test_six_inch_lines_on_every_support
    six = ->(y) { P.call(y, 84.15, 168.3, 0, '6"') }
    { 'A' => [160.0], 'B' => [200.0], 'C' => [330.0, 600.0], 'D' => [330.0, 540.0] }.each do |t, ys|
      ys.each do |y|
        r = SS::Std.build(t, [six.call(y)])
        refute r.info[:nominal], "#{t}: 6\" at #{y}"
        assert_equal [y], r.carried.map { |p| p[:y] }
        assert(r.bom.any? { |b| b[:key] == 'ub 1/2 168' }, "#{t}: U-bolt 1/2\" on the 6\"")
      end
    end
    # past the arm's end / into a frame's front post: noted, not carried
    { 'B' => 430.0, 'D' => 690.0 }.each do |t, y|
      r = SS::Std.build(t, [six.call(y)])
      assert r.info[:nominal], t
      assert(r.notes.any? { |n| n.include?('6"') }, t)
    end
  end

  # Guide points where the drawn pipes rest (their underside on the
  # steel); a drawn place a pipe already took has none.
  def test_guides_where_the_pipes_rest
    assert_equal [[200.0, 0.0], [430.0, 0.0]], SS::Std.build('B').info[:rests]
    one = SS::Std.build('B', [P.call(200, 84.15, 168.3, 0, '6"')])
    assert_equal [[430.0, 0.0]], one.info[:rests], 'the other drawn place keeps its guide'
    assert_equal [[430.0, 24.15]], one.info[:guides]
    c = SS::Std.build('C')
    assert_equal [650.0, 50.0], c.info[:rests].max, 'steam: on its shoe'
    assert_empty SS::Std.build('D', [P.call(290, 84.15, 168.3), P.call(650, 80.15, 60.3, 25.0), P.call(500, 289.85, 60.3)])
      .info[:rests]
  end

  # A point picked on a support (Plant Piping's pipe tool): where the
  # underside of the pipe drawn there goes.
  def test_where_a_pipe_drawn_onto_the_steel_rests
    at = ->(*a) { SS::Std.rest(*a)&.slice(:z, :bare, :half) }
    assert_equal({ z: 0.0, bare: false, half: 25.0 }, at.call('B', 250.0, 0.4), 'on the arm')
    assert_equal({ z: 0.0, bare: false, half: 20.0 }, at.call('A', 100.0, 0.0))
    assert_equal({ z: 0.0, bare: false, half: 25.0 }, at.call('D', 400.0, 0.0), 'on the bottom member')
    assert_equal({ z: 50.0, bare: true, half: 25.0 }, at.call('D', 600.0, 0.0), 'near the steam: onto its shoe')
    assert_nil SS::Std.rest('D', 50.0, 0.0), 'inside the back post'
    assert_nil SS::Std.rest('B', 250.0, -50.0)
    assert_equal({ z: 525.0, bare: true, half: 100.0 }, at.call('C', 435.0, 425.0), 'a line on top (2.0): onto its shoe')
    assert_equal({ z: 0.0, bare: false, half: 25.0 }, at.call('B', 200.0, 30.15), "2.0.4's guide at the 2\" centre")
  end

  # A pipe drawn into the steel the pipes sit on: the steel stays as
  # placed, the pipe is noted.
  def test_a_pipe_drawn_into_the_steel_is_noted
    r = SS::Std.build('B', [P.call(200, 30.15, 168.3, 0, '6"'), P.call(430, 24.15, 48.3, 0, '1½"')])
    assert_equal [430.0], r.carried.map { |p| p[:y] }
    assert(r.notes.any? { |n| n.include?('6"') && n.include?('จมในเหล็ก 54 มม.') })
    deep = SS::Std.build('D', [P.call(330, -300, 168.3, 0, 'low')])
    refute(deep.notes.any? { |n| n.include?('จม') }, 'well below the frame: not in its steel')
  end

  # Picked on a support: the pipe goes to the nearest of the drawing's
  # places it fits that no pipe takes (within 120 mm), else where picked.
  def test_pipes_drawn_onto_a_support_go_to_the_drawn_places
    six = { od: 168.3, ins: 0.0 }
    one = { od: 48.3, ins: 0.0 }
    assert_equal 200.0, SS::Std.rest('B', 110.0, 0.0, six)[:y], 'by the column: 0.20'
    assert_equal 430.0, SS::Std.rest('B', 465.0, 0.0, one)[:y], 'by the arm end: 0.43'
    assert_equal 465.0, SS::Std.rest('B', 465.0, 0.0, six)[:y], 'a 6" does not fit at 0.43: where picked'
    taken = [P.call(200, 84.15, 168.3)]
    assert_equal 430.0, SS::Std.rest('B', 330.0, 0.0, one, taken)[:y], 'the next free place'
    assert_equal 330.0, SS::Std.rest('B', 330.0, 0.0, six, taken)[:y], 'none free for a 6": where picked'
    assert_equal 650.0, SS::Std.rest('D', 600.0, 0.0, six)[:y], 'the nearest place a 6" fits'
    assert_equal 380.0, SS::Std.rest('C', 380.0, 425.0, { od: 114.3, ins: 50.0 })[:y], 'on top: no drawn place since 2.3'
    assert_equal 200.0, SS::Std.rest('B', 250.0, 0.0)[:y], 'size not known (Plant Piping 1.16.2)'
  end

  # ---------- E ----------

  def test_e_as_drawn
    e = SS::Std.build('E', nil, {}, { chord: { z: 900.0, r: 50.8 } })
    e.part.solids.each { |role, sol| assert SS::Mesh.closed?(sol), "E #{role}" }
    assert_equal [230.0, 565.0], e.carried.map { |p| p[:y] }, 'the drawing: 0.23 and 0.565 from the end'
    assert_equal [[230.0, 0.0], [565.0, 0.0]], e.info[:rests]
    st = steel(e)
    member = st.select { |p| p[2] <= 0.0 }
    assert_equal [0.0, 800.0], range(member, 1), 'C 4" 0.80 long'
    assert_equal [-100.0, 0.0], range(member, 2)
    assert_equal 900.0 - 50.8, st.map { |p| p[2] }.max.round(3), 'the clips touch the round member'
    assert_equal '3/8', e.info[:rod], 'rods by load: one tier as drawn'
    rods = e.bom.find { |b| b[:cat] == 'rod' }
    assert_equal 2, rods[:qty]
    assert_equal 1, e.bom.count { |b| b[:cat] == 'steel' }
    assert_equal 2, e.bom.count { |b| b[:cat] == 'plate' && b[:key] == 'clip' }
    assert_equal 2, e.bom.count { |b| b[:key] == 'ubt 1/2 102' }, 'U-bolt over the round member'
    assert_equal 0, e.info[:anchors]
    assert e.ok?
    # rods 0.70 apart, 0.05 in from the ends, hung in the clips
    rod_pts = e.part.solids.select { |r, _| r == :galv }.map { |_, sol| sol.polys.flatten(1) }
                .select { |pts| pts.map { |q| q[2] }.minmax.reduce(:-).abs > 500 }
    assert_equal [50.0, 750.0], rod_pts.map { |pts| (pts.map { |q| q[1] }.sum / pts.size).round(1) }.sort
    assert_raises(ArgumentError) { SS::Std.build('E', nil, {}, { chord: { z: 100.0, r: 50.0 } }) }
  end

  def test_e2_second_tier_as_far_as_cs_top_member
    gap = SS::Std.top_level(SS::Std.type('C'))
    assert_equal 420.0, gap
    e2 = SS::Std.build('E2', nil, {}, { chord: { z: 1300.0, r: 50.8 } })
    assert_equal 2, e2.info[:tiers]
    assert_equal [[230.0, 0.0], [565.0, 0.0], [230.0, gap], [565.0, gap]], e2.info[:rests]
    assert_equal 2, e2.bom.count { |b| b[:cat] == 'steel' }
    assert_equal '1/2', e2.info[:rod], 'two tiers: more on the rods'
    assert_match(/2 ชั้น/, e2.info[:title])
    # pipes stacked on E: two tiers, each its U-bolts; one into the steel: noted
    pipes = [P.call(230, 84.15, 168.3, 0, '6"'), P.call(300, gap + 30.15, 60.3, 0, '2" บน'),
             P.call(560, gap - 20.0, 60.3, 0, 'x')]
    e = SS::Std.build('E', pipes, {}, { chord: { z: 1300.0, r: 50.8 }, gap: gap })
    assert_equal [230.0, 300.0], e.carried.map { |p| p[:y] }
    assert(e.notes.any? { |n| n.include?('x') && n.include?('จมในเหล็ก') })
    one = SS::Std.build('E', [P.call(400, gap + 60.0, 60.3)], {}, { chord: { z: 1300.0, r: 50.8 } })
    assert one.info[:nominal], 'one tier: a pipe up there is not on it'
    assert(one.notes.any? { |n| n.include?('ไม่อยู่ในตำแหน่ง') })
  end

  def test_pipes_drawn_onto_e_go_to_its_places
    geo = { 'chord' => { 'z' => 1300.0, 'r' => 50.8 }, 'gap' => 420.0 }
    six = { od: 168.3, ins: 0.0 }
    low = SS::Std.rest('E2', 150.0, 0.0, six, [], geo: geo)
    assert_equal [0.0, 230.0], [low[:z], low[:y]]
    up = SS::Std.rest('E2', 600.0, 420.0, { od: 114.3, ins: 50.0 }, [], geo: geo)
    assert_equal [420.0, 565.0], [up[:z], up[:y]]
    assert_nil SS::Std.rest('E', 400.0, 420.0, six, [], geo: { 'chord' => { 'z' => 900.0, 'r' => 50.8 } }), 'one tier'
    assert_nil SS::Std.rest('E', 30.0, 0.0), 'outside the rods'
  end

  # The user's new C / D (2.3): 6" water 0.19 inside the post, 2" steam +
  # insulation on a shoe between guides 0.12 inside the front post, 2" air
  # hung under the top member (U-bolt up through it).
  def test_c_and_d_as_newly_drawn
    %w[C D].each do |t|
      r = SS::Std.build(t)
      r.part.solids.each { |role, sol| assert SS::Mesh.closed?(sol), "#{t} #{role}" }
      assert_equal [290.0, 500.0, 650.0], r.carried.map { |p| p[:y] }.sort, t
      at = ->(y) { r.carried.find { |p| p[:y] == y } }
      assert_in_delta 84.15, at.call(290.0)[:z], 1e-6, "#{t}: 6\" on the bottom member"
      assert_in_delta 320.0 - 30.15, at.call(500.0)[:z], 1e-6, "#{t}: air hung under the top member"
      assert_in_delta 50.0 + 30.15, at.call(650.0)[:z], 1e-6, "#{t}: steam on its shoe"
      assert_equal [[290.0, 0.0], [500.0, 320.0], [650.0, 50.0]], r.info[:rests].sort, "#{t}: guides"
      assert_equal %w[ub\ 1/2\ 168 ub\ 3/8\ 60].map { |k| k.delete('\\') }.sort,
                   r.bom.select { |b| b[:cat] == 'ubolt' }.map { |b| b[:key] }.sort, "#{t}: no U-bolt on the steam"
      assert(r.bom.any? { |b| b[:key] == 'shoe' }, "#{t}: shoe")
      assert_equal 2, r.bom.count { |b| b[:cat] == 'steel' && b[:key] == 'L50' }, "#{t}: guides"
      assert_equal [-100.0, 420.0], range(steel(r), 2), "#{t}: nothing on top any more"
      # the air's U-bolt goes up through the top member's lower flange
      ub = r.part.solids.map { |_, sol| sol.polys.flatten(1) }.select { |pts| pts.map { |q| q[1] }.minmax.then { |a, b| a > 450 && b < 550 } }
      assert(ub.any? { |pts| pts.map { |q| q[2] }.max > 320.0 + 7.5 && pts.map { |q| q[2] }.min < 320.0 - 60.3 })
    end
  end

  def test_pipes_drawn_onto_the_new_c
    six = SS::Std.rest('C', 310.0, 0.0, { od: 168.3, ins: 0.0 })
    assert_equal [290.0, 0.0, false], six.values_at(:y, :z, :bare)
    stm = SS::Std.rest('C', 630.0, 0.0, { od: 60.3, ins: 25.0 })
    assert_equal [650.0, 50.0, true], stm.values_at(:y, :z, :bare), 'onto the shoe: the bare pipe on it'
    air = SS::Std.rest('C', 520.0, 320.0, { od: 60.3, ins: 0.0 })
    assert_equal 500.0, air[:y]
    assert_in_delta 320.0 - 60.3, air[:z], 1e-6, 'under the top member: its top touches it'
    # drawn there, each carried its own way
    pipes = [P.call(290, 84.15, 168.3, 0, '6"'), P.call(500, 320.0 - 30.15, 60.3, 0, 'air'),
             P.call(650, 50.0 + 30.15, 60.3, 25.0, 'steam').merge(hot: true)]
    r = SS::Std.build('D', pipes)
    assert_equal 3, r.carried.size
    assert_empty r.notes
    refute(r.bom.any? { |b| b[:desc].include?('steam') && b[:cat] == 'ubolt' })
  end

  def test_steam_shoe_fits_the_steam_line
    low = SS::Std.build('C', [P.call(330, 84.15, 168.3), P.call(440, 420 + 5 + 60 + 57.15, 114.3, 0, 'st')])
    assert_equal 440.0, low.carried.last[:y]
    assert_in_delta 420 + 5 + 60, steel(low).map { |p| p[2] }.max, 1e-6, 'shoe leg cut to the pipe'
    high = SS::Std.build('C', [P.call(330, 84.15, 168.3), P.call(440, 420 + 5 + 150 + 57.15, 114.3, 0, 'st')])
    assert_in_delta 420 + 5 + 150, steel(high).map { |p| p[2] }.max, 1e-6, 'packed up under the shoe'
    assert(high.bom.any? { |b| b[:cat] == 'plate' })
  end
end
