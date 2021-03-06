import AlphaZero.GI
using StaticArrays

const BOARD_SIDE = 3
const NUM_POSITIONS = BOARD_SIDE ^ 2

const Player = Bool
const WHITE = true
const BLACK = false

const Cell = Union{Nothing, Player}
const Board = SVector{NUM_POSITIONS, Cell}
const INITIAL_BOARD = Board(repeat([nothing], NUM_POSITIONS))

mutable struct Game <: GI.AbstractGame
  board :: Board
  curplayer :: Player
  function Game(board=INITIAL_BOARD, player=WHITE)
    new(board, player)
  end
end

GI.Board(::Type{Game}) = Board

GI.Action(::Type{Game}) = Int

#####
##### Defining winning conditions
#####

pos_of_xy((x, y)) = (y - 1) * BOARD_SIDE + (x - 1) + 1

xy_of_pos(pos) = ((pos - 1) % BOARD_SIDE + 1, (pos - 1) ÷ BOARD_SIDE + 1)

const ALIGNMENTS =
  let N = BOARD_SIDE
  let XY = [
    [[(i, j) for j in 1:N] for i in 1:N];
    [[(i, j) for i in 1:N] for j in 1:N];
    [[(i, i) for i in 1:N]];
    [[(i, N - i + 1) for i in 1:N]]]
  [map(pos_of_xy, al) for al in XY]
end end

function has_won(g::Game, player)
  any(ALIGNMENTS) do al
    all(al) do pos
      g.board[pos] == player
    end
  end
end

#####
##### Game API
#####

const ACTIONS = collect(1:NUM_POSITIONS)

GI.actions(::Type{Game}) = ACTIONS

Base.copy(g::Game) = Game(g.board, g.curplayer)

GI.actions_mask(g::Game) = map(isnothing, g.board)

GI.board(g::Game) = g.board

function GI.board_symmetric(g::Game)
  symmetric(c::Cell) = isnothing(c) ? nothing : !c
  # Inference fails when using `map`
  @SVector Cell[symmetric(g.board[i]) for i in 1:NUM_POSITIONS]
end

GI.white_playing(g::Game) = g.curplayer

function GI.white_reward(g::Game)
  isempty(GI.available_actions(g)) && return 0.
  has_won(g, WHITE) && return 1.
  has_won(g, BLACK) && return -1.
  return nothing
end

function GI.play!(g::Game, pos)
  g.board = setindex(g.board, g.curplayer, pos)
  g.curplayer = !g.curplayer
end

#####
##### Simple heuristic for minmax
#####

function alignment_value_for(g::Game, player, alignment)
  γ = 0.3
  N = 0
  for pos in alignment
    mark = g.board[pos]
    if mark == player
      N += 1
    elseif !isnothing(mark)
      return 0.
    end
  end
  return γ ^ (BOARD_SIDE - 1 - N)
end

function heuristic_value_for(g::Game, player)
  return sum(alignment_value_for(g, player, al) for al in ALIGNMENTS)
end

function GI.heuristic_value(g::Game)
  mine = heuristic_value_for(g, g.curplayer)
  yours = heuristic_value_for(g, !g.curplayer)
  return mine - yours
end

#####
##### Machine Learning API
#####

# Vectorized representation: 3x3x3 array
# Channels: free, white, black
function GI.vectorize_board(::Type{Game}, board)
  Float32[
    board[pos_of_xy((x, y))] == c
    for x in 1:BOARD_SIDE,
        y in 1:BOARD_SIDE,
        c in [nothing, WHITE, BLACK]]
end

#####
##### Symmetries
#####

function generate_dihedral_symmetries()
  N = BOARD_SIDE
  rot((x, y)) = (y, N - x + 1) # 90° rotation
  flip((x, y)) = (x, N - y + 1) # flip along vertical axis
  ap(f) = p -> pos_of_xy(f(xy_of_pos(p)))
  sym(f) = map(ap(f), collect(1:NUM_POSITIONS))
  rot2 = rot ∘ rot
  rot3 = rot2 ∘ rot
  return [
    sym(rot), sym(rot2), sym(rot3),
    sym(flip), sym(flip ∘ rot), sym(flip ∘ rot2), sym(flip ∘ rot3)]
end

const SYMMETRIES = generate_dihedral_symmetries()

function GI.symmetries(::Type{Game}, board)
  return [(board[sym], sym) for sym in SYMMETRIES]
end

#####
##### Interaction API
#####

function GI.action_string(::Type{Game}, a)
  string(Char(Int('A') + a - 1))
end

function GI.parse_action(g::Game, str)
  length(str) == 1 || (return nothing)
  x = Int(uppercase(str[1])) - Int('A')
  (0 <= x < NUM_POSITIONS) ? x + 1 : nothing
end

function read_board(::Type{Game})
  n = BOARD_SIDE
  str = reduce(*, ((readline() * "   ")[1:n] for i in 1:n))
  white = ['w', 'r', 'o']
  black = ['b', 'b', 'x']
  function cell(i)
    if (str[i] ∈ white) WHITE
    elseif (str[i] ∈ black) BLACK
    else nothing end
  end
  @SVector [cell(i) for i in 1:NUM_POSITIONS]
end

function GI.read_state(::Type{Game})
  b = read_board(Game)
  nw = count(==(WHITE), b)
  nb = count(==(BLACK), b)
  if nw == nb
    Game(b, WHITE)
  elseif nw == nb + 1
    Game(b, BLACK)
  else
    nothing
  end
end

using Crayons

player_color(p) = p == WHITE ? crayon"light_red" : crayon"light_blue"
player_name(p)  = p == WHITE ? "Red" : "Blue"
player_mark(p)  = p == WHITE ? "o" : "x"

function GI.print_state(g::Game; with_position_names=true, botmargin=true)
  pname = player_name(g.curplayer)
  pcol = player_color(g.curplayer)
  print(pcol, pname, " plays:", crayon"reset", "\n\n")
  for y in 1:BOARD_SIDE
    for x in 1:BOARD_SIDE
      pos = pos_of_xy((x, y))
      c = g.board[pos]
      if isnothing(c)
        print(" ")
      else
        print(player_color(c), player_mark(c), crayon"reset")
      end
      print(" ")
    end
    if with_position_names
      print(" | ")
      for x in 1:BOARD_SIDE
        print(GI.action_string(Game, pos_of_xy((x, y))), " ")
      end
    end
    print("\n")
  end
  botmargin && print("\n")
end
