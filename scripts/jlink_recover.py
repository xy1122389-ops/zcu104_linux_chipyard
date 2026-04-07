#!/usr/bin/env python3
"""Try to recover J-Link GDB Server from a stuck state.

When GDB is killed without a clean disconnect, J-Link GDB Server
may hold the connection open and refuse new connections.

This script sends a raw GDB RSP detach packet to force J-Link
to release the stale connection.

Usage:
    python3 scripts/jlink_recover.py [host] [port]
    
Default: host=172.19.128.1, port=2331
"""

import socket
import sys
import time

host = sys.argv[1] if len(sys.argv) > 1 else "172.19.128.1"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 2331

print(f"Attempting to recover J-Link GDB Server at {host}:{port}")

for attempt in range(3):
    print(f"\n--- Attempt {attempt + 1} ---")
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    try:
        s.connect((host, port))
        print("TCP connected")
        
        # Send Ctrl-C (interrupt) first
        s.send(b'\x03')
        time.sleep(0.5)
        
        # Try to read any pending data
        s.setblocking(False)
        try:
            data = s.recv(4096)
            print(f"Received: {data[:100]}")
        except BlockingIOError:
            print("No pending data")
        s.setblocking(True)
        s.settimeout(5)
        
        # Send detach command
        s.send(b'+$D#44')
        time.sleep(1)
        try:
            data = s.recv(4096)
            print(f"Detach response: {data}")
            if b'OK' in data:
                print("SUCCESS: J-Link acknowledged detach")
                s.close()
                time.sleep(2)
                
                # Verify by trying a new connection
                s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s2.settimeout(5)
                try:
                    s2.connect((host, port))
                    print("Verification: new connection accepted!")
                    s2.send(b'+$?#3f')
                    time.sleep(1)
                    try:
                        data = s2.recv(4096)
                        print(f"Halt query response: {data[:100]}")
                        # Clean disconnect
                        s2.send(b'+$D#44')
                        time.sleep(0.5)
                        s2.recv(1024)
                    except socket.timeout:
                        pass
                    s2.close()
                    print("\nJ-Link recovered successfully!")
                    sys.exit(0)
                except Exception as e:
                    print(f"Verification failed: {e}")
                    s2.close()
                continue
        except socket.timeout:
            print("No response to detach")
        
        s.close()
    except socket.timeout:
        print(f"Connection timed out")
    except ConnectionRefusedError:
        print("Connection refused — J-Link GDB Server may not be running")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
    finally:
        try:
            s.close()
        except:
            pass
    
    time.sleep(3)

print("\nFailed to recover J-Link after 3 attempts.")
print("Please restart J-Link GDB Server on the Windows host.")
sys.exit(1)
