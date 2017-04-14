# This is a sketch of how a popepipe_zmq<->spec interface
# would work in python it is not functional

import zmq
import numpy as np
PORT = 2015

ctx = zmq.Context() # context is required to create zmq socket
socket = zmq.Socket(ctx, zmq.SUB) # make a subscriber socket
socket.connect ("tcp://localhost:%s" % PORT) # connect to the server
socket.set_hwm(10000) # set the recieve side message buffer limit
socket.setsockopt(zmq.SUBSCRIBE, "") # subscribe to all message, since all start with ""
# define a dtype to match the julia type
dtype_MassCompatibleDataProductFeb2017=np.dtype([("filt_value","f4"),("filt_phase","f4"),("rowcount",
"i8"),("pretrig_mean","f4"),("pretrig_rms","f4"),("pulse_average","f4")])

def apply_calibration(payload, ch):
    return payload["filt_value"]

def iscut(payload, ch):
    return False

def isinroi(payload,ch):
    return True

def get_counts():
    counts = 0
    while True:
        # read all available message, return when none are availble
        try:
            m = socket.recv_multipart(flags=zmq.NOBLOCK)
            ch = int(m[0])
            payload = np.fromstring(m[1],dtype_MassCompatibleDataProductFeb2017,1)[0]
            e = apply_calibration(payload,ch)
            if not iscut(payload,ch) and isinroi(payload,ch):
                counts+=1
        except zmq.ZMQError:
            print "no more data"
            break
    return counts
