#!/bin/env python

from osgeo import ogr
import sys

def main():
    wkt = sys.argv[1]
    poly = ogr.CreateGeometryFromWkt(wkt)
    env = poly.GetEnvelope()
    print env[0],env[1],env[2],env[3] 

if __name__ == "__main__":
    main()
