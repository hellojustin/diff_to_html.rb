require 'cgi'

class DiffToHtml

  attr_accessor :file_prefix

  def ln_cell(ln, side = nil)
    "<td class = 'ln' style='width:25px; padding:3px; background-color:#ddd; border-top:1px solid #bbb; border-right:1px solid #bbb; text-align:right; font-family:monospace; color:#999;'>#{ln}</td>"
  end

  #
  # helper for building the next row in the diff
  #
  def get_diff_row(left_ln, right_ln)
    result = []
    if @left.length > 0 or @right.length > 0
      modified = (@last_op != ' ')
      if modified
        removed_styles = " background-color:#fdd;"
        added_styles   = " background-color:#dfd;"
      else
        removed_styles = added_styles = ''
      end
      result << @left.map do |line| 
        x = "<tr>#{ln_cell(left_ln, 'l')}"
        if modified
          x += ln_cell(nil)
        else
          x += ln_cell(right_ln, 'r')
          right_ln += 1
        end
        x += "<td style='padding:3px; text-align:right; font-family:monospace; #{removed_styles}'>#{'-' unless removed_styles.empty?}</td><td style='padding:3px 10px; text-align:left; font-family:monospace; white-space:pre; #{removed_styles}'>#{line}</td></tr>"
        left_ln += 1
        x
      end
      if modified
        result << @right.map do |line| 
          x = "<tr>#{ln_cell(nil)}#{ln_cell(right_ln, 'r')}<td style='padding:3px; text-align:right; font-family:monospace; #{added_styles}'>#{'+' unless added_styles.empty?}</td><td style='padding:3px 10px; text-align:left; font-family:monospace; white-space:pre; #{added_styles}'>#{line}</td></tr>"
          right_ln += 1
          x
        end
      end
    end
    return result.join("\n"), left_ln, right_ln
  end

  def range_row(range)
    "<tr class='range'><td colspan=4 style='padding:3px; background-color:rgb(234,242,245); color:#999;'>... #{range}</td></tr>"
  end

  def range_info(range)
    range.match(/^@@ \-(\d+),\d+ \+(\d+),\d+ @@/)
    left_ln = Integer($1)
    right_ln = Integer($2)
    return left_ln, right_ln
  end

  def begin_file(file)
    result = <<EOF 
<li style="background-color:#eee; padding:2px; margin-bottom:10px; border:1px solid #ddd; border-radius:6px;"><h3 style="margin:5px; font-size:14px; font-weight:normal; line-height:20px;">#{file}</h3><table cellspacing=0 style="width:100%; font-size:12px; font-family:monospace; border:1px solid #bbb; border-radius:4px; border-collapse:separate; padding:0; background-color:#fff;">
EOF
  result
  end
  
  def flush_changes(result, left_ln, right_ln)
    x, left_ln, right_ln = get_diff_row(left_ln, right_ln)
    result << x
    @left.clear
    @right.clear    
    return left_ln, right_ln
  end
  
  def get_single_file_diff(file_name, diff_file)
    @last_op = ' '
    @left = []
    @right = []
  
    result = ""

    diff = diff_file.split("\n")
    
    diff.shift #index
    line = nil
    while line !~ /^---/ && !diff.empty?
      line = diff.shift
    end
    header_old = line
    if line =~ /^---/
      diff.shift #+++
      
      result << begin_file(file_name)
      range = diff.shift
      left_ln, right_ln = range_info(range)
      result << range_row(range)
      
      diff.each do |line|
        op = line[0,1]
        line = line[1..-1] || ''
        if op == '\\'
          line = op + line
          op = ' '
        end
        
        if ((@last_op != ' ' and op == ' ') or (@last_op == ' ' and op != ' '))
          left_ln, right_ln = flush_changes(result, left_ln, right_ln)
        end
        
        # truncate and escape
        line = CGI.escapeHTML(line)

        case op
        when ' '
          @left.push(line)
          @right.push(line)
        when '-' then @left.push(line)
        when '+' then @right.push(line)
        when '@' 
          range = '@' + line
          flush_changes(result, left_ln, right_ln)
          left_ln, right_ln = range_info(range)
          result << range_row(range)
        else
          flush_changes(result, left_ln, right_ln)
          result << "</table></li>"
          break
        end
        @last_op = op
      end

      flush_changes(result, left_ln, right_ln)
      result << "</table></li>"      
    else
      #"<div class='error'>#{header_old}</div>"
      result =%Q{<li style="background-color:#eee; padding:2px; border:1px solid #ddd; border-radius:6px;"><h3 style="margin:5px; font-size:14px; font-weight:normal;">#{file_name}</h3>#{header_old}</li>}
    end

    result
  end

  def file_header_pattern
    raise "Method to be implemented in VCS-specific class"
  end
  
  def get_diffs(composite_diff)
    pattern = file_header_pattern
    files   = composite_diff.split(pattern)
    headers = composite_diff.scan(pattern) #huh can't find a way to get both at once
    files.shift if files[0] == '' #first one is junk usually
    result = []
    i = 0
    files.each do |file|
      result << {:filename => "#{file_prefix}#{get_filename(headers[i])}", :file => file}
      i += 1
    end
    result
  end

  def diffs_to_html(diffs)
    result = '<ul style="margin:0; padding:0; list-style:none;">'
    @filenum = 0
    diffs.each do |file_map|
      result << get_single_file_diff(file_map[:filename], file_map[:file])
      @filenum += 1
    end
    result << '</ul>'
    result    
  end
  
  def composite_to_html(composite_diff)
    diffs_to_html get_diffs(composite_diff)
  end
end

class GitDiffToHtml < DiffToHtml
  def file_header_pattern
    /^diff --git.+/
  end

  def get_filename(file_diff)
    match = (file_diff =~ / b\/(.+)/)
    raise "not matched!" if !match
    $1
  end  
end

class SvnDiffToHtml < DiffToHtml
  def file_header_pattern
    /^Index: .+/
  end

  def get_filename(header)
    match = (header =~ /^Index: (.+)/) #if we use this pattern file_header_pattern files split doesn't work
    raise "header '#{header}' not matched!" if !match
    $1
  end  
end
