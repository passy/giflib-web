module Web.Giflib.Types where

import Data.Date (Date())
import Halogen.HTML.Target (URL())
import qualified Node.UUID as UUID

type Tag = String

type Entry = { id :: UUID.UUID
             , url :: URL
             , tags :: [Tag]
             , date :: Date
             }
