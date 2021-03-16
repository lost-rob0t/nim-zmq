import strutils
import zmq
import os
import system
import bitops
import options
import strformat

const address = "tcp://127.0.0.1:44445"
const max_msg = 10

proc receiveMultipart(socket: PSocket, flags: TSendRecvOptions): seq[string] =
  var hasMore: int = 1
  while hasMore > 0:
    result.add(socket.receive())
    hasMore = getsockopt[int](socket, RCVMORE)


proc client() =
  var d1 = connect(address, mode = DEALER)
  var d2 = connect(address, mode = DEALER)

  # Send a dummy message withc each socket to obtain the identity on the ROUTER socket
  d1.send("dummy")
  d2.send("dummy")

  var poller: Poller
  poller.register(d1, ZMQ_POLLIN)
  poller.register(d2, ZMQ_POLLIN)
  while true:
    let res = poll(poller, 1_000)
    if res > 0:
      for i in 0..<len(poller):
        if events(poller[i]):
          let buf = receiveMultipart(poller[i].socket, NOFLAGS)
          for j, msg in buf.pairs:
            echo &"CLIENT> Socket{i} received \"{msg}\""
        else:
          echo &"CLIENT> Socket{i} received nothing"

    elif res == 0:
      echo "CLIENT> Timeout"
      break

    else:
      zmqError()

  echo "CLIENT -- END"

when isMainModule:
  # Create router connexion
  var router = listen(address, mode = ROUTER)

  # Create client thread
  var thr: Thread[void]
  createThread(thr, client)

  # Use first message and store ids
  var ids: seq[string]
  ids.add(router.receive())
  discard router.receive()
  ids.add(router.receive())
  discard router.receive()
  for i in ids:
    echo "SERVER> Socket Known: ", i.toHex

  # Send message
  var num_msg = 0
  while num_msg < max_msg:
    let top = ids[num_msg mod 2]
    # Adress message to a DELAER Socket using its id
    router.send(top, SNDMORE)
    # Send data
    router.send("Hello, socket#" & top.toHex, SNDMORE)
    router.send("Your message is:", SNDMORE)
    router.send("payload#" & $num_msg)
    echo "SERVER> Send: ", num_msg, " to topic:", ids[num_msg mod 2].toHex
    inc(num_msg)
    sleep(100)

  router.close()
  joinThread(thr)

