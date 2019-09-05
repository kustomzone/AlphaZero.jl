###############################################################################
# Learning the value function with a neural network
###############################################################################

const USE_CUDA = true

const TRAIN_TEST_RATIO = 10

###############################################################################
#=
if USE_CUDA
    using CuArrays
    CuArrays.allowscalar(false)
end
=#

using Statistics
using LinearAlgebra: norm
using Flux
using Flux: onehot, onecold, crossentropy, throttle, @epochs, testmode!

import Random

using Gobblet.TicTacToe
using Gobblet.TicTacToe: make_board, available
using Gobblet.TicTacToe: encode_board, decode_board!, CARD_BOARDS
using Gobblet.TicTacToe: Solution, value, status

################################################################################
# Util functions

function minibatches(X, Y; batchsize=32)
  b = batchsize
  n = size(X, 2) ÷ b
  rng(i) = 1 + b * (i - 1) : b * i
  return ((X[:,rng(i)], Y[:,rng(i)]) for i in 1:n)
end

###############################################################################
# Build the dataset
# In Julia, you want the features matrix to be
# of shape nfeatures × nsamples (feature vectors are columns)

function TicTacToe.State(code::Int)
  B = make_board()
  decode_board!(B, code)
  State(B, first_player=Red)
end

const flatten = collect ∘ Iterators.flatten

function vectorize_board(board)
  map(board[:,l] for l in 1:NUM_LAYERS) do layer
    map(layer) do p
      Float32[isnothing(p), p == Red, p == Blue]
    end |> flatten
  end |> flatten
end

const POSSIBLE_STATE_VALUES = [-1, 0, 1]

interesting_state(st) =
  !st.finished && available(st, Red)[1] - available(st, Blue)[1] ∈ [0, 1]

function value_dataset(solution)
  x = Vector{Float32}[]
  y = Vector{Float32}[]
  codes = Int[]
  for code in 0:CARD_BOARDS-1
    st = State(code)
    if interesting_state(st)
      V = value(status(solution, code))
      push!(x, vectorize_board(st.board))
      push!(y, Float32.(onehot(V, POSSIBLE_STATE_VALUES)))
      push!(codes, code)
    end
  end
  return reduce(hcat, x), reduce(hcat, y), codes
end

const solution = solve()
X, Y, Codes = value_dataset(solution)
const N = size(X, 2)
perm = Random.randperm(N)
X, Y, Codes = X[:, perm], Y[:, perm], Codes[perm]

const Ntest = N ÷ TRAIN_TEST_RATIO
Xtest,  Ytest  = X[:,1:Ntest], Y[:,1:Ntest]
Xtrain, Ytrain = X[:,Ntest+1:end], Y[:,Ntest+1:end]

println("Dataset generated.")
println("Number of loosing, tie, and winning positions: ", Int.(sum(Y, dims=2)))

################################################################################
# Specify the model

const INPUT_DIM   = size(X, 1) # 3 * NUM_POSITIONS * NUM_LAYERS
const OUTPUT_DIM  = size(Y, 1) # length(POSSIBLE_VALUES)
const HIDDEN_SIZE = 100

NN = Chain(
  Dense(INPUT_DIM, HIDDEN_SIZE, relu),
  Dense(HIDDEN_SIZE, HIDDEN_SIZE, relu),
  Dense(HIDDEN_SIZE, HIDDEN_SIZE, relu),
  Dense(HIDDEN_SIZE, HIDDEN_SIZE, relu),
  Dense(HIDDEN_SIZE, HIDDEN_SIZE, relu),
  Dense(HIDDEN_SIZE, OUTPUT_DIM),
  softmax)

loss(x, y) = crossentropy(NN(x) .+ eps(Float32), y)

accuracy(NN, x, y) = mean(onecold(NN(x)) .== onecold(y))

maximum_weight(NN) = maximum(p -> maximum(abs.(p)), params(NN))

################################################################################

if USE_CUDA
  # Send everything to the GPU
  Xtrain, Ytrain = gpu.((Xtrain, Ytrain))
  Xtest, Ytest = gpu.((Xtest,  Ytest))
  NN = gpu(NN)
end

using Printf


function print_legend()
  @printf("%8s %8s %8s", "Accuracy", "Loss", "MaxW")
end

function evalcb()
  #a = 100 * accuracy(cpu.((NN, Xtest, Ytest))...)
  a = 0.
  l = loss(Xtrain, Ytrain)
  w = maximum_weight(NN)
  @printf("%8.1f %8.3f %8.3f\n", a, l, w)
end

function dataset(n)
  batches = minibatches(Xtrain, Ytrain, batchsize=128)
  return Iterators.take(Iterators.cycle(batches), n)
end

function fullbatch_dataset(n)
  repeated((Xtrain, Ytrain), n)
end

opt = ADAM(1e-3)

Flux.train!(loss, params(NN), dataset(1), opt)

@time Flux.train!(loss, params(NN), fullbatch_dataset(10000), opt, cb=throttle(evalcb, 2))

print(typeof(Xtrain))

# on GPU: 10.595135
# on CPU:

################################################################################
