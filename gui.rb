require 'gtk3'
require 'json'
require './server'

class Form < Gtk::Box

  attr_reader :inputs

  def initialize(*names)
    super :horizontal, 0
    @list = 2.times.map do
      vbox = Gtk::Box.new :vertical, 0
      pack_start vbox, expand: false, fill: false, padding: 10
      vbox
    end
    @inputs = {}
    @tests = {}
    add_items names
  end

  def add_items(names)
    names.each do |name, default, test, focus|
      add_label name
      add_input name, default, test, focus == :focus
    end
  end

  def add_label(name)
    label = Gtk::Label.new "#{name}:"
    label.set_alignment 0, 0.5
    @list.first.pack_start label, expand: true, fill: false, padding: 5
  end

  def add_input(name, default, test, focus)
    input = Gtk::Entry.new
    input.placeholder_text = default
    @list.last.pack_start input, expand: true, fill: false, padding: 5
    input.grab_focus if focus
    @inputs[name] = input
    @tests[name] = test
  end

  def data
    map = {}
    @inputs.each do |name, input|
      text = input.text
      text = text.empty? ? input.placeholder_text : text
      map[name] = text
    end
    map
  end

  def data_valid?
    data.all? { |name, text| text =~ @tests[name] }
  end
end

class NewDialog < Gtk::Dialog

  def initialize(app)
    super title: '輸入基本資訊', flags: :destroy_with_parent
    label = Gtk::Label.new '請輸入本節點的資訊'
    content_area.pack_start label, expand: false, fill: false, padding: 10
    nickname = '暱稱'
    ip = 'IP'
    port = 'Port'
    form = Form.new([nickname, '阿華', /^.*$/],
                    [ip, '127.0.0.1', /^\d+\.\d+\.\d+\.\d+$/],
                    [port, '2001', /^\d+$/, :focus])
    content_area.pack_start form, expand: false, fill: false, padding: 0
    signal_connect 'response' do |log, res|
      if res == Gtk::ResponseType::OK.to_i
        app.name = form.data[nickname]
        app.init_server form.data[ip], form.data[port]
      end
    end
    ok = add_button '確定', Gtk::ResponseType::OK
    [nickname, ip, port].each do |name|
      form.inputs[name].signal_connect 'key-release-event' do
        ok.sensitive = form.data_valid?
      end
    end
    add_button '取消', Gtk::ResponseType::CANCEL
    show_all
    run
    destroy
  end
end

class JoinDialog < Gtk::Dialog

  class << self

    def join(btn, form)
      btn.toplevel.server.join form.data['IP'], form.data['Port']
    end
  end

  def initialize(btn)
    super title: '加入聊天室', flags: :destroy_with_parent
    label = Gtk::Label.new '請輸入預加入節點的資訊'
    content_area.pack_start label, expand: false, fill: false, padding: 10
    form = Form.new(['IP', '127.0.0.1', /^\d+\.\d+\.\d+\.\d+$/],
                    ['Port', '2001', /^\d+$/, :focus])
    content_area.pack_start form, expand: false, fill: false, padding: 0
    signal_connect 'response' do |log, res|
      if res == Gtk::ResponseType::OK.to_i
        JoinDialog.join btn, form
      end
    end
    ok = add_button '確定', Gtk::ResponseType::OK
    ['IP', 'Port'].each do |name|
      form.inputs[name].signal_connect 'key-release-event' do
        ok.sensitive = form.data_valid?
      end
    end
    add_button '取消', Gtk::ResponseType::CANCEL
    show_all
    run
    destroy
  end
end

class App < Gtk::Window

  attr_reader :server

  class << self

    def receive_message(sender_id, msg, app)
      app.add_message sender_id, msg
    end

    def quit(btn)
      Gtk.main_quit
      server = btn.toplevel.server
      server.leave if server
    end
  end

  def initialize
    @messages = []
    super
    init_ui
    NewDialog.new self
  end

  def init_ui
    top_window
    init_vbox do |vbox|
      menu vbox
      drawing_panel vbox
      input_bar vbox
    end
    show_all
  end

  def top_window
    set_title '點對點聊天室'
    signal_connect 'destroy', &App.method(:quit)
    set_default_size 500, 500
    set_window_position :center
  end

  def init_vbox
    vbox = Gtk::Box.new :vertical, 2
    yield vbox
    add vbox
  end

  def menu(vbox)
    bar = Gtk::Toolbar.new
    bar.set_toolbar_style Gtk::Toolbar::Style::ICONS
    join, quit = [:NEW, :QUIT].map do |stock|
      Gtk::ToolButton.new stock_id: Gtk::Stock.const_get(stock)
    end
    join.signal_connect 'clicked', &JoinDialog.method(:new)
    quit.signal_connect 'clicked', &App.method(:quit)
    [join, quit].each.with_index do |btn, i|
      bar.insert btn, i
    end
    vbox.pack_start bar, expand: false, fill: false, padding: 0
  end

  def drawing_panel(vbox)
    @draw = Gtk::DrawingArea.new
    @draw.signal_connect 'draw' do
      on_draw
    end
    @draw.override_background_color :normal, Gdk::RGBA.new(1, 1, 1, 1)
    vbox.pack_start @draw, expand: true, fill: true, padding: 0
  end

  def on_draw
    context = @draw.window.create_cairo_context
    w, h = [:width, :height].map do |attr|
      @draw.allocation.public_send attr
    end
    radius = 120
    draw_separator context, w, h
    draw_circle context, w, h, radius
    if @server
      draw_node context, radius, @server.id
      draw_name context, radius, @server.id, '你'
    end
    draw_messages context, radius
  end

  # c = cairo context
  def draw_separator(c, w, h)
    c.set_line_width 0.5
    c.set_source_rgba 0.8, 0.8, 0.8, 1
    c.move_to 0, 1
    c.line_to w, 1
  end

  def draw_circle(c, w, h, radius)
    c.set_source_rgba 0, 0, 0, 1
    c.move_to radius + w / 2, h / 2
    c.translate w / 2, h / 2
    c.arc 0, 0, radius, 0, 2 * Math::PI
    c.stroke
  end

  def add_message(sender_id, msg)
    max_msg_size = 20
    @messages.unshift id: sender_id, msg: msg
    @messages.pop if @messages.size > max_msg_size
    @draw.queue_draw
  end

  def draw_messages(c, radius)
    c.select_font_face 'Droid Sans Fallback',
      Cairo::FONT_SLANT_NORMAL, Cairo::FONT_WEIGHT_NORMAL
    c.set_font_size 12
    authors_msgs = {}
    @messages.each do |data|
      json = JSON.parse data[:msg]
      name, msg = [json['name'], json['msg']]
      authors_msgs[name] ||= 0
      draw_name c, radius, data[:id], name if authors_msgs[name] == 0
      draw_msg c, radius, data[:id], msg, authors_msgs[name]
      authors_msgs[name] += 1
      draw_node c, radius, data[:id]
    end
  end

  def draw_name(c, radius, id, name)
    init_font c
    c.set_source_rgba 0, 0, 0, 1
    x, y = node_position radius - 25, id
    c.move_to x, y
    c.show_text name
  end

  def draw_msg(c, radius, id, msg, no)
    init_font c
    c.set_source_rgba 0, 0, 0, no == 0 ? 1 : 0.5
    x, y = node_position radius + 20, id
    msg = "「#{msg}」"
    c.move_to x > 0 ? x : x - msg.size * font_size, y - no * 15
    c.show_text msg
  end

  def init_font(c)
    c.select_font_face 'Droid Sans Fallback',
      Cairo::FONT_SLANT_NORMAL, Cairo::FONT_WEIGHT_NORMAL
    c.set_font_size font_size 
  end

  def font_size
    12
  end

  def draw_node(c, radius, id)
    c.set_source_rgb *node_color
    x, y = node_position radius, id
    c.arc x, y, 5, 0, 2 * Math::PI
    c.fill
  end

  def node_color
    [74, 134, 232].map { |x| x.to_f / 255 }
  end

  def node_position(radius, id)
    theta = 2 * Math::PI * id / @server.max_nodes
    x, y = [:cos, :sin].map do |method|
      radius * Math.public_send(method, theta)
    end
    [y, - x]
  end

  def input_bar(vbox)
    hbox = Gtk::Box.new :horizontal, 5
    hbox.set_border_width 5
    @name = Gtk::Label.new ''
    hbox.add @name
    entry = Gtk::Entry.new
    entry.signal_connect 'activate' do
      @server.send_msg JSON[name: @name.text, msg: entry.text]
      add_message @server.id, JSON[name: '', msg: entry.text]
      entry.text = ''
    end
    hbox.pack_start entry, expand: true, fill: true, padding: 0
    vbox.pack_start hbox, expand: false, fill: false, padding: 0
  end

  def name=(name)
    @name.text = name
  end

  def init_server(host, port)
    cb = App.method :receive_message
    @server = Server.new host, port.to_i, cb, self
    @server.start
  end
end

Gtk.init
App.new
Gtk.main
