module StackBump.Spinner where

import Control.Concurrent
import Control.Concurrent.Async
import Control.Monad
import System.Console.ANSI
import System.Exit
import System.IO
  ( BufferMode (NoBuffering),
    hFlush,
    hPutStrLn,
    hSetBuffering,
    stderr,
    stdout,
  )
import System.IO.Unsafe
import System.Process

spinner :: Int -> String
spinner i = (states !! (i `mod` l)) : ""
  where
    states :: String
    states = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    l :: Int
    l = length states

counter :: MVar Int
counter = unsafePerformIO (newMVar 0)
{-# NOINLINE counter #-}

displaySpinner :: String -> Async () -> IO ()
displaySpinner title action = do
  hSetBuffering stdout NoBuffering
  setSGR [SetColor Foreground Dull White]
  putStr " > "
  setSGR [SetColor Foreground Vivid White]
  putStr (title <> " ")
  setSGR [SetColor Foreground Vivid Magenta]
  putStr "⠋"
  a <-
    async $
      forever $ do
        currentCount <- modifyMVar counter (\i -> return (i + 1, i))
        cursorBackward 1
        setSGR
          [SetColor Foreground Vivid Magenta, SetConsoleIntensity BoldIntensity]
        putStr (spinner currentCount)
        hFlush stdout
        threadDelay (50 * 1000)
  wait action
  cancel a
  clearLine
  setCursorColumn 0

runProcessWithSpinner :: String -> IO ()
runProcessWithSpinner title =
  case words title of
    (c : args) -> runProcessWithSpinnerRaw title c args
    _ -> exitFailure

runProcessWithSpinnerRaw :: String -> String -> [String] -> IO ()
runProcessWithSpinnerRaw title c args = do
  a <-
    async $ do
      (ec, out, err) <- readProcessWithExitCode c args ""
      when (ec /= ExitSuccess) $ do
        setSGR [SetColor Foreground Vivid Red]
        hPutStrLn stderr out
        hPutStrLn stderr err
        setSGR [Reset]
        error $ title <> " failed with " <> show ec
  displaySpinner title a
