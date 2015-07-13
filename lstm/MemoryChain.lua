local MemoryChain, parent = torch.class('lstm.MemoryChain', 'nn.Module')

function MemoryChain:__init(inputSize, hiddenSize, maxLength)
  print("MemoryChain("..inputSize..','..hiddenSize..','..maxLength..')')
  parent.__init(self)
  self.inputSize = inputSize
  self.hiddenSize = hiddenSize
  self.maxLength = maxLength
  self.gradInput = nil
  self.lstms = {}
  -- Later we will cache the batch size and length of the input during the
  -- forward so we don't bother recomputing these during the backward pass.
  self.batchSize = nil
  self.len = nil

  print("Creating MemoryChain")
  -- make enough lstm cells for the longest sequence
  for i=1,maxLength do
    self.lstms[i] = lstm.MemoryCell(inputSize, hiddenSize)
  end
  -- We will use the firt cell as the storage for shared parameters, but
  -- we can't share them until later, after the whole network is created 
  -- because getParameters will point the tensors to new storage.
  self.lstm_params, self.lstm_grad_params = self.lstms[1]:parameters()
end

-- share parameters among all memory cells
function MemoryChain:share()
  -- make all other parameter tensors reference that memory.
  for i=2,self.maxLength do
    local cell_params, cell_grad_params = self.lstms[i]:parameters()
    for k=1, #cell_params do
      cell_params[k]:set(self.lstm_params[k])
      cell_grad_params[k]:set(self.lstm_grad_params[k])
    end
  end
end

function MemoryChain:reset(radius)
  local par = self:parameters()
  for i=1, #par do
    par[i]:uniform(-radius, radius)
  end
end

function MemoryChain:parameters()
  return self.lstm_params, self.lstm_grad_params
end

-- If input is 3D then the first dimension is batch, otherwise the first dim
-- is the sequence. Last dimension is features.
function MemoryChain:updateOutput(input)
  if input:dim() == 3 then
    self.batchSize = input:size(1)
    self.len = input:size(2)
  elseif input:dim() == 2 then
    self.batchSize = 1
    self.len = input:size(1)
  else
    error("expecting either 2D or 3D input")
  end
  -- Standarize our view of the input so we can always count on the first dimension
  -- being batch size, the second length, and third the number of input featuers.
  local inputView = input:view(self.batchSize, self.len, self.inputSize)
  -- The first memory cell will receive zeros.
  local h = lstm.Tensor()(self.batchSize, self.hiddenSize):zero()
  local c = lstm.Tensor()(self.batchSize, self.hiddenSize):zero()
  -- Store inputs of each memory cell so we have these for the backwards pass.
  self.hidden_states = {[0] = h}
  self.memories = {[0] = c}
  -- Iterate over memory cells feeding each successive tuple (h,c) into the next
  -- LSTM memory cell.
  for i=1,self.len do
    local x = inputView:select(2, i)
    self.lstms[i]:forward({x, h, c})
    h, c = unpack(self.lstms[i].output)
    self.hidden_states[i] = h
    self.memories[i] = c
  end
  self.output = self.lstms[self.len].output
  return self.output
end

function MemoryChain:updateGradInput(input, gradOutput)
  local h,c
  local inputView = input:view(self.batchSize, self.len, self.inputSize)
  self.gradInput = lstm.Tensor()(self.batchSize, self.len, self.inputSize)
  for i=len,1,-1 do
    local x = inputView:select(2,i)
    h = self.hidden_states[i-1]
    c = self.memories[i-1]
    self.lstms[i]:backward({x,h,c}, gradOutput)
    gradOutput = self.lstms[i].gradInput
    -- Only h and c propagate back to the next cell, the gradient wrt x gets stored
    -- in gradInput.
    self.gradInput:select(2, i):copy(gradOutput[1])
    gradOutput = {gradOutput[2], gradOutput[3]}
  end
  return self.gradInput
end

-- This happens automatically when calling backward on the individual memory
-- cells in updateGradInput. Not sure what to do about the scale parameter.
function MemoryChain:accGradParameters(input, gradOutput, scale)
end

function MemoryChain:type(type)
  self.gradInput = {}
  return parent.type(self, type)
end

return MemoryChain

-- END
