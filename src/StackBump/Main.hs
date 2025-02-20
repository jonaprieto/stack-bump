module StackBump.Main where

import Control.Lens hiding ((.=))
import Control.Monad
import Data.Aeson.Lens
import Data.ByteString.Char8 qualified as ByteString (pack, unpack)
import Data.List qualified as List
import Data.Maybe
import Data.Monoid
import Data.Text qualified as Text
import Data.Yaml
import StackBump.Spinner
import System.Console.ANSI
import System.Environment
import System.Exit
import System.FilePath
import System.FilePath.Glob
import System.IO.Strict
import Text.Read
import Prelude hiding (readFile)

data BumpType
  = BumpTypeOther Int
  | BumpTypePatch
  | BumpTypeMinor
  | BumpTypeMajor
  deriving stock (Show, Eq)

data Options = Options
  { optsBumpType :: BumpType,
    optsVerify :: Bool
  }

data Package
  = Package String

bumpPackage :: BumpType -> IO (Either String (String, String))
bumpPackage bt = do
  ~pkg <- lines <$> readFile "package.yaml"
  let mi = List.findIndex ("version" `List.isPrefixOf`) pkg
  case mi of
    Nothing -> return (Left "No `version` to bump")
    Just i -> do
      -- TODO: use NonEmptyList instead
      let (p, versionStr : ps) = splitAt i pkg -- Partial, but can't be
          ev = decodeEither (ByteString.pack versionStr) :: Either String Value
          vstring = ev ^. _Right . key "version" . _String
          vstringS = map Text.unpack (Text.split (== '.') vstring)
          ebv = List.intercalate "." <$> bump bt vstringS
      case ebv of
        Left e -> return (Left e)
        Right bv -> do
          let packageYaml' =
                unlines
                  ( p
                      <> [ init
                             (ByteString.unpack (encode (object ["version" .= bv])))
                         ]
                      <> ps
                  )
          return (Right (packageYaml', bv))

bump :: BumpType -> [String] -> Either String [String]
bump = \case
  BumpTypeMajor -> \case
    (n : ns) -> (: map (const "0") ns) . show . (+ (1 :: Int)) <$> readEither n
    _ -> Left "Can't major bump"
  BumpTypeMinor -> \case
    (n1 : n : ns) -> (\x -> n1 : x : map (const "0") ns) . show . (+ (1 :: Int)) <$> readEither n
    _ -> Left "Can't minor bump"
  BumpTypePatch -> \case
    (n1 : n2 : n : ns) -> (\x -> n1 : n2 : x : map (const "0") ns) . show . (+ (1 :: Int)) <$> readEither n
    _ -> Left "Can't patch bump"
  BumpTypeOther c -> \ns -> 
    if | c >= length ns -> Left ("Can't bump " <> show c <> " component")
       | otherwise -> 
          case splitAt c ns of
            (n1, n:n2) -> (\x -> n1 <> (x : map (const "0") n2)) . show . (+ (1 :: Int)) <$>
              readEither n
            _ -> Left "Unexpected case."


readOptions :: [String] -> Either String Options
readOptions as = do
  bt <-
    case as of
      ["other"] -> Left usage
      ("other" : x : _) -> BumpTypeOther <$> readEither x
      ("patch" : _) -> Right BumpTypePatch
      ("minor" : _) -> Right BumpTypeMinor
      ("major" : _) -> Right BumpTypeMajor
      _ -> Left usage
  let verify =
        case as of
          (_ : "-v" : _) -> True
          (_ : "--verify" : _) -> True
          _ -> False
  return $ Options bt verify

runTasks :: String -> IO a -> IO ()
runTasks title action = do
  setSGR [SetColor Foreground Vivid Yellow]
  putChar '•'
  setSGR [SetColor Foreground Vivid Black]
  putStrLn (" " <> title)
  _ <- action
  cursorUp 1
  clearLine
  setCursorColumn 0
  setSGR [SetColor Foreground Vivid Green]
  putChar '✓'
  setSGR [SetColor Foreground Vivid Black]
  putStrLn (" " <> title)

run :: Options -> IO ()
run Options {..} = do
  ev <- bumpPackage optsBumpType
  case ev of
    Left e -> error e
    Right (packageYaml', v) -> do
      when optsVerify $ runTasks "Checking if package is good for publishing" $ do
        runProcessWithSpinner "stack build"
        runProcessWithSpinner "stack test"
        runProcessWithSpinner "stack sdist"

      runTasks ("Writting new version (v" <> v <> ")") $
        writeFile "package.yaml" packageYaml'

      runTasks ("Commiting (v" <> v <> ")") $ do
        when optsVerify $ runProcessWithSpinner "stack build"
        unless optsVerify $ runProcessWithSpinner "hpack"
        runProcessWithSpinner "git add package.yaml"
        mcabalFile <- findCabalfile
        case mcabalFile of
          Just cabalFile -> runProcessWithSpinner ("git add " <> cabalFile)
          Nothing -> return ()
        runProcessWithSpinnerRaw
          "git commit -m ..."
          "git"
          ["commit", "-m", "Bump version to v" <> v]
        runProcessWithSpinner ("git tag v" <> v)
      putStrLn ""
      setSGR [SetColor Foreground Vivid White]
      putStrLn ("Bumped version to: v" <> v)

findCabalfile :: IO (Maybe FilePath)
findCabalfile = do
  mgitIgnore <- listToMaybe <$> glob ".gitignore"
  case mgitIgnore of
    Nothing -> findCabalfile'
    Just gitIgnore -> do
      gitIgnoreC <- lines <$> readFile gitIgnore
      let ignoringCabalFile =
            isJust $ List.find ((== ".cabal") . takeExtension) gitIgnoreC
      if ignoringCabalFile
        then return Nothing
        else findCabalfile'
  where
    findCabalfile' = listToMaybe <$> glob "./*.cabal"

usage :: String
usage = "Usage: stack-bump <patch|minor|major|other <n>> [--verify|-v]"

main :: IO ()
main = do
  as <- getArgs
  when (listToMaybe as == Just "help") $ do
    putStrLn usage
    exitSuccess
  case readOptions as of
    Left err -> error err
    Right opts -> run opts
