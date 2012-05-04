#! /bin/bash

# resets the keystone database back to empty tables.

echo 'drop database keystone' | mysql
echo 'create database keystone' | mysql
keystone-manage db_sync
