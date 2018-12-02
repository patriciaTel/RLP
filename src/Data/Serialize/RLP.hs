-- |
-- Module      : Data.Serialize.RLP
-- License     : LGPL-3 (see LICENSE)
--
-- Maintainer  : Javier Sagredo <jasataco@gmail.com>
-- Stability   : stable
--
-- An implementation of the Recursive Length Prefix method
-- as described in the Yellow Paper <https://ethereum.github.io/yellowpaper/paper.pdf>.
--
-- To actually use this module, the type that is going to
-- be encoded has to be instance of the RLPSerialize defining
-- 'toRLP' and 'fromRLP'.
--------------------------------------------------------------------------------

module Data.Serialize.RLP (
  -- * The RLP Type
  RLPT(..),
  -- ** Subtleties
  -- $subtleties

  -- * Helper Int functions
  toBigEndian,
  toBigEndianS,
  fromBigEndian,
  fromBigEndianS,

  -- * Helper String functions
  toByteString,
  toByteStringS,
  fromByteString,
  fromByteStringS,
  
  -- * The RLPSerialize class
  RLPSerialize(..)
  -- * Example
  -- $example
  
) where

import Data.Serialize.RLP.Internal

import qualified Data.ByteString              as DBS
import qualified Data.ByteString.Lazy         as DBSL

--------------------------------------------------------------------------------

-- $subtleties
-- The idea of transforming a custom type into RLPT is to
-- preserve the original structure as far as possible. For example,
-- suppose we have a data structure:
--
-- > data Name   = (String, String)   -- represents the first and last name of a Person
-- > data Person = Person Name Int    -- represents the whole name of a Person and its age
--
-- Then the desired output of the transformation of a Person value to RLPT should be (pseudocode):
--
-- > RLPL [ RLPL [ RLPB, RLPB ], RLPB ]
--
-- This way the structure is clearly preserved. Eventhough this does not have
-- to be true as the transformation to RLPL is defined by the user and a custom
-- process can be implemented, it is advised to follow this guideline for better
-- understanding of the generated code.
--
-- It is important to remark that although it can't be imposed, it doesn't make sense to try
-- to transform to RLP types with more than one constructor. The transformation should encode
-- a way to find out which of the constructors belongs to the data so not only data is being
-- encoded in the result, also information about the structure futher than the actual length
-- prefixes. That's why it only makes sense to transform to RLP types with just one constructor.

--------------------------------------------------------------------------------

-- | The 'RLPSerialize' class provides functions for transforming values to RLPT structures.
-- For encoding and decoding values with the RLP protocol, 'toRLP' and 'fromRLP' have to
-- be implemented.
--
-- Instances of RLPSerialize have to satisfy the following property:
--
-- > fromRLP . toRLP == id
--
-- In such case, it can be assured with the default definition that:
--
-- > rlpDecode . rlpEncode == id
--
-- RLPSerialize makes use of the Get and Put classes together with a set of
-- custom serializations for encoding and decoding RLPT data.
class RLPSerialize a where
  -- | Transform a value to the 'RLPT' structure that best fits its internal structure
  toRLP :: a -> RLPT
  -- | Transform an 'RLPT' structure back into the value it represents
  fromRLP :: RLPT -> a

  -- | Transform a value to an 'RLPT' structure and then encode it following the
  -- RLP standard.
  rlpEncode :: a -> DBSL.ByteString
  rlpEncode = rlpEncodeI . toRLP

  -- | Transform a ByteString to an 'RLPT' structure following the RLP standard and
  -- then transform it to the original type.
  rlpDecode :: DBSL.ByteString -> Maybe a
  rlpDecode x = maybe Nothing fromRLP $ rlpDecodeI x

  {-# MINIMAL toRLP, fromRLP #-}

-- RLPT values don't have to be transformed as they already are RLPT
instance RLPSerialize RLPT where
  toRLP = id

  fromRLP = id

-- ByteStrings just have to be encapsulated
-- Also, it only makes sense to disencapsulate from a ByteString
instance RLPSerialize DBS.ByteString where
  toRLP = RLPB

  fromRLP (RLPB b) = b
  fromRLP _ = undefined

-- Ints have to be transformed into its Big-endian form
-- and then they are treated as ByteStrings.
-- The same applies for the inverse transformation. They
-- are treated as ByteStrings and then interpreted as a
-- Big-endian encoded Int.
instance RLPSerialize Int where
  toRLP = toRLP . toBigEndianS

  fromRLP = fromBigEndianS . (fromRLP :: RLPT -> DBS.ByteString)

-- Serializing lists implies make a list with the serialization
-- of each element
instance RLPSerialize a => RLPSerialize [a] where
  toRLP = RLPL . map toRLP

  fromRLP (RLPL x) = map fromRLP x
  fromRLP _        = undefined

-- Bools are serialized as [0] or [1] in a ByteArray
-- THIS IS AN ASUMPTION considering Bool equivalent to
-- integers in the range 0..1
instance RLPSerialize Bool where
  toRLP True = RLPB $ toByteStringS "\SOH"
  toRLP False = RLPB $ toByteStringS "\NUL"

  fromRLP x
    | x == toRLP True = True
    | otherwise       = False
 
-- Tuples are transformed into Lists
instance (RLPSerialize a, RLPSerialize b) => RLPSerialize (a, b) where
  toRLP (x, y) = RLPL [toRLP x, toRLP y]

  fromRLP (RLPL [x, y]) = (fromRLP x, fromRLP y)
  fromRLP _             = undefined

instance (RLPSerialize a, RLPSerialize b, RLPSerialize c) => RLPSerialize (a, b, c) where
  toRLP (x, y, z) = RLPL [toRLP x, toRLP y, toRLP z]

  fromRLP (RLPL [x, y, z]) = (fromRLP x, fromRLP y, fromRLP z)
  fromRLP _                = undefined

instance (RLPSerialize a, RLPSerialize b, RLPSerialize c, RLPSerialize d) => RLPSerialize (a, b, c, d) where
  toRLP (a1, a2, a3, a4) = RLPL [toRLP a1, toRLP a2, toRLP a3, toRLP a4]

  fromRLP (RLPL [a1, a2, a3, a4]) = (fromRLP a1, fromRLP a2, fromRLP a3, fromRLP a4)
  fromRLP _                       = undefined

instance (RLPSerialize a, RLPSerialize b, RLPSerialize c, RLPSerialize d, RLPSerialize e) => RLPSerialize (a, b, c, d, e) where
  toRLP (a1, a2, a3, a4, a5) = RLPL [toRLP a1, toRLP a2, toRLP a3, toRLP a4, toRLP a5]

  fromRLP (RLPL [a1, a2, a3, a4, a5]) = (fromRLP a1, fromRLP a2, fromRLP a3, fromRLP a4, fromRLP a5)
  fromRLP _                           = undefined

instance (RLPSerialize a, RLPSerialize b, RLPSerialize c, RLPSerialize d, RLPSerialize e, RLPSerialize f) => RLPSerialize (a, b, c, d, e, f) where
  toRLP (a1, a2, a3, a4, a5, a6) = RLPL [toRLP a1, toRLP a2, toRLP a3, toRLP a4, toRLP a5, toRLP a6]

  fromRLP (RLPL [a1, a2, a3, a4, a5, a6]) = (fromRLP a1, fromRLP a2, fromRLP a3, fromRLP a4, fromRLP a5, fromRLP a6)
  fromRLP _                               = undefined

-- Needed by the default rlpDecode implementation
instance RLPSerialize a => RLPSerialize (Maybe a) where
  toRLP = undefined

  fromRLP = Just . fromRLP

--------------------------------------------------------------------------------

-- $example
-- For a full example, we reproduce the implementation of the Person type as in the
-- subtleties section.
--
-- First of all, we define the type:
--
-- > type Name = (String, String)
-- > data Person = Person {
-- >                    name :: Name,
-- >                    age  :: Int
-- >                } deriving (Show)
--
-- Then we have to make it an instance of RLPSerialize:
--  
-- > instance RLPSerialize Person where
-- >   toRLP p = RLPL [
-- >                 RLPL [
-- >                     toRLP . toByteStringS . fst . name $ p,
-- >                     toRLP . toByteStringS . snd . name $ p
-- >                     ],
-- >                 toRLP . age $ p]
-- > 
-- >   fromRLP (RLPL [ RLPL [ RLPB a, RLPB b ], RLPB c ]) =
-- >          Person (fromByteStringS a, fromByteStringS b) (fromBigEndianS c :: Int)
-- 
-- This way, if the decoding gives rise to other structure than the expected, a runtime
-- exception will be thrown by the pattern matching. We can now use our decoder and encoder
-- with our custom type:
--
-- > p = Person ("John", "Snow") 33
-- > e = rlpEncode p
-- > -- "\204\202\132John\132Snow!" ~ [204,202,132,74,111,104,110,132,83,110,111,119,33]
-- > rlpDecode e :: Maybe Person
-- > -- Just (Person {name = ("John","Snow"), age = 33})
--
