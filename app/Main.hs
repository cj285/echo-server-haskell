module Main where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 (unpack)
import GHC.Event
import Network.Socket
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent.STM
import Control.Concurrent (forkIO)
import System.Posix.Types

main :: IO ()
main = do
  maybeEM <- getSystemEventManager
  existEM <- case maybeEM of
    Just em -> return em
    Nothing -> error "You somehow do not have a system event manager"
  sock <- socket AF_INET Stream 0
  setSocketOption sock ReuseAddr 1
  bind sock (SockAddrInet 8080 (tupleToHostAddress (127, 0, 0, 1)))
  listen sock 20
  mainLoop sock existEM

mainLoop :: Socket -> EventManager -> IO ()
mainLoop sock em = do
  (conn, addr) <- accept sock
  (rq, wq)<- allocateRWQueues
  _ <- registerFd em (doAction rq conn addr) (socket2Fd conn) evtRead MultiShot
  _ <- forkIO (echoWork rq wq)
  _ <- forkIO (respWork wq)
  mainLoop sock em

echoWork :: TQueue ByteString -> TQueue ByteString -> IO ()
echoWork rq wq = do
  msg <- atomically $ readTQueue rq
  atomically $ writeTQueue wq msg
  echoWork rq wq

respWork :: TQueue ByteString -> IO ()
respWork rq = do
  msg <- atomically $ readTQueue rq
  putStr $ unpack msg
  respWork rq

doAction ::  TQueue ByteString -> Socket -> SockAddr -> IOCallback
doAction rq conn addr _fdkey thisEvent
    | thisEvent == evtRead = doRead rq conn addr
    | otherwise = error "this is seriously impossible "

doRead :: TQueue ByteString -> Socket -> SockAddr -> IO ()
doRead rq conn _addr = do
  msg <- NSB.recv conn 4
  atomically $ writeTQueue rq msg

socket2Fd :: Socket -> Fd
socket2Fd (MkSocket cfd _ _ _ _) = Fd cfd

allocateRWQueues :: IO (TQueue ByteString, TQueue ByteString)
allocateRWQueues = do
    rq <- newTQueueIO
    wq <- newTQueueIO
    return (rq, wq)
