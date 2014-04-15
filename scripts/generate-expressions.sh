#!/bin/sh

. $(dirname $0)/env.sh

mkdir -p $NGDART_SCRIPT_DIR/gen

cat $NGDART_BASE_DIR/test/core/parser/generated_getter_setter.dart  | \
    sed -e 's/_template;/_generated;/' | \
    grep -v REMOVE  > $NGDART_BASE_DIR/gen/generated_getter_setter.dart
$DART $NGDART_BASE_DIR/bin/parser_generator_for_spec.dart getter_setter >> \
    $NGDART_BASE_DIR/gen/generated_getter_setter.dart
