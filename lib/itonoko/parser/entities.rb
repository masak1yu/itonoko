# frozen_string_literal: true

module Itonoko
  module Parser
    ENTITIES = {
      "amp"    => "&",
      "lt"     => "<",
      "gt"     => ">",
      "quot"   => '"',
      "apos"   => "'",
      "nbsp"   => " ",
      "copy"   => "©",
      "reg"    => "®",
      "trade"  => "™",
      "mdash"  => "—",
      "ndash"  => "–",
      "laquo"  => "«",
      "raquo"  => "»",
      "ldquo"  => "“",
      "rdquo"  => "”",
      "lsquo"  => "‘",
      "rsquo"  => "’",
      "hellip" => "…",
      "bull"   => "•",
      "euro"   => "€",
      "yen"    => "¥",
      "pound"  => "£",
      "cent"   => "¢",
      "deg"    => "°",
      "plusmn" => "±",
      "times"  => "×",
      "divide" => "÷",
      "frac12" => "½",
      "frac14" => "¼",
      "frac34" => "¾",
      "sup2"   => "²",
      "sup3"   => "³",
      "micro"  => "µ",
      "para"   => "¶",
      "middot" => "·",
      "cedil"  => "¸",
      "acute"  => "´",
      "uml"    => "¨",
      "macr"   => "¯",
      "szlig"  => "ß",
      "agrave" => "à", "aacute" => "á", "acirc" => "â",
      "atilde" => "ã", "auml"   => "ä", "aring" => "å",
      "aelig"  => "æ", "ccedil" => "ç", "egrave" => "è",
      "eacute" => "é", "ecirc"  => "ê", "euml"  => "ë",
      "igrave" => "ì", "iacute" => "í", "icirc" => "î",
      "iuml"   => "ï", "eth"    => "ð", "ntilde" => "ñ",
      "ograve" => "ò", "oacute" => "ó", "ocirc" => "ô",
      "otilde" => "õ", "ouml"   => "ö", "oslash" => "ø",
      "ugrave" => "ù", "uacute" => "ú", "ucirc" => "û",
      "uuml"   => "ü", "yacute" => "ý", "thorn" => "þ",
      "yuml"   => "ÿ",
      "Agrave" => "À", "Aacute" => "Á", "Acirc" => "Â",
      "Atilde" => "Ã", "Auml"   => "Ä", "Aring" => "Å",
      "AElig"  => "Æ", "Ccedil" => "Ç", "Egrave" => "È",
      "Eacute" => "É", "Ecirc"  => "Ê", "Euml"  => "Ë",
      "Igrave" => "Ì", "Iacute" => "Í", "Icirc" => "Î",
      "Iuml"   => "Ï", "ETH"    => "Ð", "Ntilde" => "Ñ",
      "Ograve" => "Ò", "Oacute" => "Ó", "Ocirc" => "Ô",
      "Otilde" => "Õ", "Ouml"   => "Ö", "Oslash" => "Ø",
      "Ugrave" => "Ù", "Uacute" => "Ú", "Ucirc" => "Û",
      "Uuml"   => "Ü", "Yacute" => "Ý", "THORN" => "Þ",
    }.freeze

    def self.decode_entity(name)
      if name.start_with?("#x", "#X")
        [name[2..].to_i(16)].pack("U")
      elsif name.start_with?("#")
        [name[1..].to_i].pack("U")
      else
        ENTITIES[name] || "&#{name};"
      end
    end
  end
end
