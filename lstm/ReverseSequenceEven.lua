local ReverseSequenceEven, parent = torch.class('lstm.ReverseSequenceEven', 'nn.Module')

-- This unit takes as input a tensor with the shape BxLxK and it reverses
-- the L direction. This is appropriate for batches of sequences that are
-- all the same length.
--
--    lstm.ReverseSequenceEven(timeDim)(inputs)
--
-- The timeDim skips the first dimension, so if the shape is BxTxK then timeDim
-- should be 1 because the time dimension is the first dimenion after the batch
-- dimenion. This parameterization was chosen to match ReverseSequence(), which
-- works in either batch or non-batch mode.
--
-- This module is only designed to work with mini-batch (not individual examples). For
-- a single sequence, ReverseSequence() can be used.
function ReverseSequenceEven:__init(timeDimension, forwardOnly)
  parent.__init(self)
  if timeDimension == nil or timeDimension <= 0 then
    error("Invalid timeDimension: " .. timeDimension)
  end
  self.timeDimension = timeDimension
  self.indices = torch.LongTensor()
  self.gradInput = lstm.Tensor()
end

-- This module has no parameters.
function ReverseSequenceEven:parameters()
  return {}
end

function ReverseSequenceEven:reverse(dest, src)
  dest:resizeAs(src)
  local timeSteps = src:size(self.timeDimension+1)
  if self.indices:dim() ~= 1 or self.indices:size(1) ~= timeSteps then
    self.indices:resize(timeSteps):copy(torch.range(timeSteps, 1, -1))
  end
  dest:indexCopy(self.timeDimension+1, self.indices, src)
  return dest
end

function ReverseSequenceEven:updateOutput(inputs)
  return self:reverse(self.output, inputs)
end

function ReverseSequenceEven:updateGradInput(inputs, upstreamGradOutput)
  return self:reverse(self.gradInput, upstreamGradOutput)
end

-- END
