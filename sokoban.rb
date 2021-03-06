#!/usr/bin/ruby -w

require 'curses'
require 'gosu'
require 'matrix'

include Curses

class Sokoban

  attr_accessor :map_state, :game_window, :game_won, :player_pos, :moves,
                :playing, :gosu_walk_empty_space_track,
                :gosu_walk_push_barrel_track, :gosu_walk_into_wall_track,
                :gosu_barrel_completed_track, :gosu_game_won_track

  def play
    init show_menu
    playing = true

    while playing
      if !is_game_won || moves.zero?
        draw_map
        process_input
      else
        unless @game_won
          @game_window.close
          refresh
          @game_won = true
          @gosu_game_won_track.play
          game_won_win = Curses::Window.new 50, 300, 20, 60
          game_won_win.clear
          game_won_win.addstr "You win!! Completed in #{@moves} moves! You're kickin' rad!"
          game_won_win.refresh
          refresh
        end
      end
    end
  end

  def setup_sound_tracks
    @gosu_walk_empty_space_track = Gosu::Sample.new('sounds/walk_empty_space.wav')
    @gosu_walk_push_barrel_track = Gosu::Sample.new('sounds/walk_push_barrel.wav')
    @gosu_walk_into_wall_track = Gosu::Sample.new('sounds/walk_into_wall.wav')
    @gosu_barrel_completed_track = Gosu::Sample.new('sounds/barrel_completed.wav')
    @gosu_game_won_track = Gosu::Sample.new('sounds/game_won.wav')
  end

  def show_menu
    Curses.init_screen
    Curses.start_color
    menu_window = Curses::Window.new 50, 500, 0, 0
    menu_window.setpos 20,70
    menu_window.addstr 'Welcome to '
    menu_window.setpos 20,81
    init_pair(COLOR_YELLOW, COLOR_YELLOW, COLOR_BLACK)
    init_pair(COLOR_RED, COLOR_RED, COLOR_BLACK)
    init_pair(COLOR_MAGENTA, COLOR_MAGENTA, COLOR_BLACK)
    menu_window.attron(color_pair(COLOR_YELLOW) | A_NORMAL) do
      menu_window.addstr 'Sokoban Reborn:'
    end
    menu_window.setpos 20, 96
    menu_window.attron(color_pair(COLOR_RED) | A_NORMAL) do
      menu_window.addstr ' Wrath of the Warehouse!'
    end
    menu_window.setpos 22,70
    menu_window.addstr 'Choose a level:'
    menu_window.setpos 23,70
    menu_window.addstr "1: Peasant's floor"
    menu_window.setpos 24,70
    menu_window.addstr "2: Peasant Master's floor"
    menu_window.setpos 25,70
    menu_window.addstr "3: Middle Manager's Lair"
    menu_window.setpos 26,70
    menu_window.addstr "4: VP's Hollow"
    menu_window.setpos 27,70
    menu_window.addstr "5: The Grandmaster's Office"
    menu_window.refresh
    menu_window.attron Curses::A_INVIS
    level_chosen = ''
    level_chosen = process_menu_input menu_window.getch while level_chosen == '' || level_chosen.nil?
    menu_window.attroff Curses::A_INVIS
    menu_window.close
    level_chosen
  end

  def process_menu_input(input)
    "maps/level_#{input}.map" if input =~ /[1-5]/
  end

  def log_message(message)
    File.open 'log.log', 'a' do |logfile|
      logfile.puts message.to_s
    end
  end

  def init(map)
    File.open 'log.log', 'w' do |logfile|
      logfile.puts ''
    end

    populate_map_state map
    setup_sound_tracks
    Curses.refresh
  end

  def populate_map_state(map)
    @moves = 0
    @map_state = Array.new(100).map! { Array.new(100).map! { (?\ ) } }
    max_width = 0
    cur_line = 0
    cur_col = 0
    File.open map, 'r' do |infile|
      while (line = infile.gets)
        max_width = line.to_s.length > max_width ? line.to_s.length : max_width
        line.chomp.chars.each do |character|
          next if character.nil?
          @map_state[cur_line][cur_col] = character
          @player_pos = Vector[cur_line, cur_col] if character == ?@
          cur_col += 1
        end
        cur_col = 0
        cur_line += 1
      end
    end
    resize_map_state max_width, cur_line
    initialize_game_window max_width, cur_line
  end

  def resize_map_state(width, height)
    @map_state = @map_state.each do |row_arr|
      @map_state[@map_state.index row_arr] = row_arr[0..(width - 2)]
    end
    @map_state = @map_state[0..(height - 1)]
  end

  def initialize_game_window(width, height)
    @game_window = Curses::Window.new height, (width - 1), 20, 70
    @game_window.clear
    draw_map
  end

  def process_input
    input = @game_window.getch
    case input
      when ?q
        @game_window.close
        exit 0
      when ?w, ?a, ?s, ?d
        move input
      when ?r
        @game_window.close
        init
        draw_map
    end
    @moves += 1
  end

  def move(direction)
    future_player_pos = determine_future_pos direction, false
    @player_pos = resolve_move future_player_pos, direction
  end

  def play_sound(future_floor_type)
    case future_floor_type
      when ?., (?\ )
        @gosu_walk_empty_space_track.play
      when ?o, ?*
        @gosu_walk_push_barrel_track.play
      when ?#
        @gosu_walk_into_wall_track.play
    end
  end

  def resolve_move(future_player_pos, direction)
    # Resolve state of future cells
    future_map_char = get_map_char_from_vector future_player_pos
    play_sound future_map_char
    case future_map_char
      when ?.
        set_map_char_at_vector ?+, future_player_pos
      when (?\ )
        set_map_char_at_vector ?@, future_player_pos
      when ?o
        future_crate_position = determine_future_pos direction, true
        future_crate_char = get_map_char_from_vector future_crate_position
        case future_crate_char
          when ?.
            set_map_char_at_vector ?*, future_crate_position
          when (?\ )
            set_map_char_at_vector ?o, future_crate_position
          else
            return @player_pos
        end
        set_map_char_at_vector ?@, future_player_pos
      when ?*
        future_crate_position = determine_future_pos direction, true
        future_crate_char = get_map_char_from_vector future_crate_position
        case future_crate_char
          when ?.
            set_map_char_at_vector ?*, future_crate_position
            @gosu_barrel_completed_track.play
          when (?\ )
            set_map_char_at_vector ?o, future_crate_position
          else
            return @player_pos
        end
        set_map_char_at_vector ?+, future_player_pos
      else
        return @player_pos
    end

    # Resolve state of player cell
    case get_map_char_from_vector @player_pos
      when ?@
        set_map_char_at_vector (?\ ), @player_pos
      when ?+
        set_map_char_at_vector (?.), @player_pos
    end

    @player_pos = future_player_pos
  end

  def determine_future_pos(direction, predicting_crate)
    prediction_size = predicting_crate ? 2 : 1
    if direction == ?w
      Vector[@player_pos[0] - prediction_size, @player_pos[1]]
    elsif direction == ?a
      Vector[@player_pos[0], @player_pos[1] - prediction_size]
    elsif direction == ?s
      Vector[@player_pos[0] + prediction_size, @player_pos[1]]
    else
      Vector[@player_pos[0], @player_pos[1] + prediction_size]
    end
  end

  def get_map_char_from_vector(position_vector)
    @map_state[position_vector[0]][position_vector[1]]
  end

  def set_map_char_at_vector (newchar, position_vector)
    @map_state[position_vector[0]][position_vector[1]] = newchar
  end

  def draw_map
    @game_window.clear
    convert_map_to_string.each_char do |char|
      case char
        when ?#
          @game_window.attron(color_pair(COLOR_MAGENTA) | A_NORMAL) do
            @game_window.addstr char
          end
        when ?o, ?*, ?.
          @game_window.attron(color_pair(COLOR_YELLOW) | A_NORMAL) do
            @game_window.addstr char
          end
        else
          @game_window.attron(color_pair(A_NORMAL) | A_NORMAL) do
            @game_window.addstr char
          end
      end
    end
    @game_window.refresh
  end

  def convert_map_to_string
    map_string = ''
    @map_state.each do |col|
      col.each do |cell|
        map_string += cell
      end
    end
    map_string
  end

  def is_game_won
    (!convert_map_to_string.include? ?+) && (!convert_map_to_string.include? ?.)
  end

end
