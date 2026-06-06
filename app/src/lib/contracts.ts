import GradPadFactoryArtifact from '../../abis/GradPadFactory.json'
import GradPadTokenArtifact from '../../abis/GradPadToken.json'
import MockUSDArtifact from '../../abis/MockUSDC.json'

export const ADDRESSES = {
  GradPadFactory: '0xc2aae1bdfb4d178b8a0d72750e10ffb98813948a' as `0x${string}`,
  MockUSDC:       '0x7b851635eea924e8501e733909fcf91ab1b98348' as `0x${string}`,
} as const

export const ABIS = {
  GradPadFactory: GradPadFactoryArtifact.abi,
  GradPadToken:   GradPadTokenArtifact.abi,
  MockUSDC:       MockUSDArtifact.abi,
} as const
