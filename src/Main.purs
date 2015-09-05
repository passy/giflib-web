module Main where

import Prelude

import qualified DOM.HTML as DOM
import qualified DOM.HTML.Types as DOM
import qualified DOM.HTML.Window as DOM
import qualified DOM.Node.Node as DOM
import qualified DOM.Node.ParentNode as DOM
import qualified DOM.Node.Types as DOM
import qualified Data.Date as Date
import qualified Data.Date.UTC as Date
import qualified Data.Foreign as Foreign
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.StrMap as StrMap
import qualified Halogen.HTML as H
import qualified Halogen.HTML.Core as H
import qualified Halogen.HTML.Properties as P
import qualified Halogen.HTML.Events as E
import qualified Halogen.HTML.Events.Forms as E
import qualified Halogen.HTML.Events.Handler as E
import qualified Halogen.HTML.Events.Types as E
import qualified MDL as MDL
import qualified MDL.Button as MDL
import qualified MDL.Spinner as MDL
import qualified MDL.Textfield as MDL
import qualified Node.UUID as NUUID
import qualified Web.Firebase as FB
import qualified Web.Firebase.DataSnapshot as DS
import qualified Web.Firebase.Types as FB

import Control.Error.Util (hush)
import Control.Monad.Aff (Aff(), runAff)
import Control.Monad.Eff (Eff())
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Console (log, CONSOLE())
import Control.Monad.Eff.Exception (error, throwException)
import Control.Monad.Free (liftFI)
import Control.Monad.Reader
import Control.Monad.Reader.Class
import Control.Monad.Reader.Trans
import Control.MonadPlus (guard)
import Control.Plus (empty)
import Css.Background (BackgroundImage(..), backgroundImage)
import Css.String (fromString)
import Data.Argonaut.Core (JObject(), fromObject)
import Data.Argonaut.Decode (decodeJson)
import Data.Argonaut.Encode (encodeJson)
import Data.Bifunctor (lmap, rmap)
import Data.Either (Either(Left, Right), either)
import Data.Either.Unsafe (fromRight)
import Data.Enum (fromEnum)
import Data.Foldable (all, intercalate)
import Data.Functor (($>))
import Data.Generic (Generic, gEq, gShow)
import Data.Identity (Identity(), runIdentity)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Monoid (mempty)
import Data.String (joinWith, trim, split)
import Data.Tuple (Tuple(..))
import Data.URI (runParseURI, parseURI, printURI)
import Data.URI.Types (URI())
import Halogen.Query (modify, gets, get)


import Web.Giflib.Internal.Unsafe
import Web.Giflib.Types (Tag(), Entry(..), UUID(..), uuid, runUUID, runEntryList)
import Web.Giflib.DOM.Util (appendToQuerySelector)
import Web.Giflib.HTML.CSS.Unsafe (style)

import Halogen
import Halogen.Component
import Halogen.Effects

data LoadingStatus
 = Loading
 | Loaded
 | LoadingError String

derive instance genericLoadingStatus :: Generic LoadingStatus

instance eqLoadingStatus :: Eq LoadingStatus where
  eq = gEq

instance showLoadingStatus :: Show LoadingStatus where
  show = gShow

newtype State = State { entries       :: Array Entry   -- ^ All entries matching the tag
                      , tag           :: Maybe Tag     -- ^ Currently selected tag, if any
                      , newUrl        :: Maybe URI     -- ^ New URI to be submitted
                      , newTags       :: Set.Set Tag   -- ^ New Tags to be submitted
                      , error         :: String        -- ^ Global UI error to be shown
                      , loadingStatus :: LoadingStatus -- ^ List loading state
                      }

data Input a
  = NoOp a
  | ResetNewForm a
  | AddNewEntry a
  | LoadingAction LoadingStatus a
  | UpdateNewURI String a
  | UpdateNewTags String a
  | UpdateEntries (Array Entry) a
  | ShowError String a

newtype AppConfig = AppConfig { firebase :: FB.Firebase }

type AppEffects eff = HalogenEffects ( uuid :: NUUID.UUIDEff
                                     , console :: CONSOLE
                                     , now :: Date.Now
                                     , firebase :: FB.FirebaseEff | eff)

initialState :: State
initialState = State { entries: mempty
                     , tag: mempty
                     , newUrl: empty
                     , newTags: mempty
                     , error: mempty
                     , loadingStatus: Loading
                     }

resetState :: State -> State
resetState (State st) =
  State $ st { newUrl = empty, newTags = mempty }

canSaveState :: State -> Boolean
canSaveState (State s) =
  all isJust [s.newUrl, s.newTags] && s.loadingStatus == Loaded

newEntry :: State -> UUID -> Date.Date -> Maybe Entry
newEntry (State s) uuid now = do
  uri <- s.newUrl
  let tags = s.newTags
  guard $ s.loadingStatus == Loaded

  return $ Entry { id: uuid
                , uri: uri
                , tags: tags
                , date: now
                }

-- | Handle a request to an external service
{-- handler :: forall eff m. --}
{--   AppConfig -> --}
{--   Request -> --}
{--   E.Event (AppEff eff) Action --}
{-- handler (AppConfig conf) (AddNewEntry s) = do --}
{--   id' <- liftEff NUUID.v4 --}
{--   now <- liftEff Date.now --}
{--   let entry = Entry { id: uuid $ show id' --}
{--                     , tags: s.newTags --}
{--                     , url: s.newUrl --}
{--                     , date: now --}
{--                     } --}

{--   -- TODO: Would be nice to have a MonadReader/ReaderT for this. Like, really --}
{--   -- nice. But I'm too stupid. --}
{--   children <- liftEff $ FB.child "entries" conf.firebase --}
{--   liftEff $ FB.push (Foreign.toForeign $ unsafeShowPrintId $ encodeJson entry) Nothing children --}
{--   E.yield ResetNewForm --}

ui :: forall g p. (Functor g) => Component State Input g p
ui = component render eval
  where
    render :: Render State Input p
    render (State st) = H.div [ P.class_ $ H.className "gla-content" ] $
      [ H.form [ E.onSubmit (const $ E.preventDefault $> action NoOp)
               , P.class_ $ H.className "gla-layout--margin-h"
               ]
               [ H.div [ P.class_ $ H.className "gla-form--inline-group" ] [
                 MDL.textfield [ E.onValueChange $ E.input UpdateNewURI ] $
                   MDL.defaultTextfield { id = Just "inp-new-gif"
                                        , label = Just "URL"
                                        , type_ = "url"
                                        } ]
               , H.div [ P.class_ $ H.className "gla-form--inline-group" ] [
                 MDL.textfield [ E.onValueChange $ E.input UpdateNewTags ] $
                   MDL.defaultTextfield { id = Just "inp-new-tags"
                                        , label = Just "Tags"
                                        } ]
               , H.div [ P.class_ $ H.className "gla-form--inline-group" ] [
                 MDL.button $
                   MDL.defaultButton { text = "Add GIF"
                                     , elevation = MDL.ButtonRaised
                                     } ]
               ]
      , MDL.spinner (st.loadingStatus == Loading)
      , H.div [ P.class_ $ H.className "gla-card-holder" ] $ map entryCard st.entries
      ]

    entryCard :: Render Entry Input p
    entryCard (Entry e) = H.div
        [ P.classes [ MDL.card, MDL.shadow 3 ]
        , P.key $ runUUID e.id
        ]
        [ H.div [ P.class_ MDL.cardImageContainer
        , style $ backgroundImage $ entryBackground e
                ] []
        , H.div [ P.class_ MDL.cardHeading ]
            [ H.h2
                [ P.class_ MDL.cardHeadingText ] [ H.text $ formatEntryTags e ]
            ]
        , H.div [ P.class_ MDL.cardCaption ] [ H.text $ formatEntryDatetime e ]
        , H.div [ P.class_ MDL.cardBottom ]
            [ H.a
                [ P.href $ printURI e.uri
                , P.class_ MDL.cardUri
                , P.target "_blank" ] [ H.text $ printURI e.uri ]
            ]
        ]

    entryBackground :: forall e. { uri :: URI | e } -> BackgroundImage
    entryBackground e =
      let url = "url(" <> printURI e.uri <> ")"
      in BackgroundImage $ fromString url

    -- All of them are no-ops for now.
    eval :: Eval Input State Input g
    eval (NoOp next) =
      pure next
    eval (AddNewEntry next) = do
      id' <- liftFI NUUID.v4
      now <- liftFI Date.now
      (State state) <- get
      pure next
    eval (ResetNewForm next) =
      modify resetState $> next
    eval (LoadingAction status next) =
      modify (\(State s) -> State $ s { loadingStatus = status }) $> next
    eval (UpdateNewURI str next) =
      modify (\(State s) -> State $ s { newUrl = hush $ runParseURI str }) $> next
    eval (UpdateNewTags str next) =
      modify (\(State s) -> State $ s { newTags = processTagInput str }) $> next
    eval (UpdateEntries entries next) =
      modify (\(State s) -> State $ s { entries = entries }) $> next
    eval (ShowError str next) =
      modify (\(State s) -> State $ s { error = str }) $> next


addEntry :: forall eff. Entry -> Aff ( firebase :: FB.FirebaseEff | eff ) Unit
addEntry = do
  -- Shit, we do I get the conf from?
  -- children <- FB.child "entries" conf.firebase
  -- FB.push (Foreign.toForeign $ unsafeShowPrintId $ encodeJson entry) Nothing children
  return unit

formatEntryDatetime :: forall e. { date :: Date.Date | e } -> String
formatEntryDatetime e =
  intercalate "-" $ [ show <<< toNumber <<< getYear <<< Date.year $ e.date
                    , show <<< (+1) <<< fromEnum <<< Date.month $ e.date
                    , show <<< toNumber <<< getDay <<< Date.dayOfMonth $ e.date ]
  where
    getDay :: Date.DayOfMonth -> Int
    getDay (Date.DayOfMonth i) = i
    getYear :: Date.Year -> Int
    getYear (Date.Year i) = i

formatEntryTags :: forall e. { tags :: Set.Set Tag | e } -> String
formatEntryTags e = joinWith " " $ map (\x -> "#" ++ x) $ List.fromList $ Set.toList e.tags

processTagInput :: String -> Set.Set Tag
processTagInput = trim >>> split " " >>> List.toList >>> Set.fromList

-- Application Main
main :: Eff (AppEffects ()) Unit
main = runAff throwException (const $ pure unit) $ do
  liftEff $ log "Booting. Beep. Boop."

  app <- runUI ui initialState
  mainEl <- liftEff $ appendToQuerySelector "#app-main" app.node

  case mainEl of
    Just _ -> pure unit
    Nothing -> liftEff <<< throwException $ error "Couldn't find #app-main. What've you done to my HTML?"

  -- This *should* break loudly.
  let fbUri = fromRight $ runParseURI "https://giflib-web.firebaseio.com/"
  fb <- liftEff $ FB.newFirebase fbUri
  children <- liftEff $ FB.child "entries" fb
  {-- FB.on FB.Value (dscb app.driver) Nothing children --}
  let conf = AppConfig { firebase: fb }

  liftEff $ log "Up and running."

  where
    -- TODO: Use Aff instead of Eff for this.
    {-- dscb :: forall req eff. (Action -> eff) -> FB.DataSnapshot -> eff --}
    {-- dscb driver ds = --}
    {--   case (Foreign.unsafeReadTagged "Object" $ DS.val ds) >>= decodeEntries of --}
    {--     Right entries -> driver (LoadingAction Loaded $ UpdateEntries entries) --}
    {--     Left  err     -> driver $ ShowError $ show err --}

    decodeEntries :: JObject -> Either Foreign.ForeignError (Array Entry)
    decodeEntries = rmap runEntryList <<< lmap Foreign.JSONError <<< decodeJson <<< fromObject
