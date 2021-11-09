#!/bin/bash

# This simple and stupid functions are created
# for making unit testing possible; we can mock 
# a function, but we can not mock an expression
# so that we wrap the expression in a function.

function utils_is_a_file
{
    local _path="$1"
    [ -f "${_path}" ]
}

function utils_is_a_symlink
{
    local _path="$1"
    [ -L "${_path}" ]
}

function utils_is_a_directory
{
    local _path="$1"
    [ -d "${_path}" ]
}

function utils_path_exists
{
    local _path="$1"
    [ -e "${_path}" ]
}

function utils_is_not_empty_str
{
    local _str="$1"
    [ -n "${_str}" ]
}

function utils_is_empty_str
{
    local _str="$1"
    [ -z "${_str}" ]
}

function utils_is_executable
{
    local _path="$1"
    [ -x "${_path}" ]
}
