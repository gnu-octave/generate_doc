## Copyright (C) 2008 Soren Hauberg <soren@hauberg.org>
## Copyright (C) 2014-2016 Julien Bect <jbect@users.sourceforge.net>
## Copyright (C) 2015 Oliver Heimlich <oheim@posteo.de>
## Copyright (C) 2016 Fernando Pujaico Rivera <fernando.pujaico.rivera@gmail.com>
## Copyright (C) 2017 Olaf Till <i7tiol@t-online.de>
##
## This program is free software; you can redistribute it and/or modify it
## under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 3 of the License, or (at
## your option) any later version.
##
## This program is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
## General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; see the file COPYING.  If not, see
## <http://www.gnu.org/licenses/>.

## -*- texinfo -*-
## @deftypefn {Function File} generate_package_html (@var{name}, @var{outdir}, @var{options})
## Generate @t{HTML} documentation for a package.
##
## The function reads information about package @var{name} using the
## package system. This is then used to generate bunch of
## @t{HTML} files; one for each function in the package, and one overview
## page. The files are all placed in the directory @var{outdir}, which defaults
## to the current directory. The @var{options} structure is used to control
## the design of the web pages.
##
## As an example, the following code generates the web pages for the @t{image}
## package, with a design suitable for the @t{Octave-Forge} project.
##
## @example
## options = get_html_options ("octave-forge");
## generate_package_html ("image", "image_html", options);
## @end example
##
## The resulting files will be available in the @t{"image_html"} directory. The
## overview page will be called @t{"image_html/overview.html"}.
##
## As a convenience, if @var{options} is a string, a structure will
## be generated by calling @code{get_html_options}. This means the above
## example can be reduced to the following.
##
## @example
## generate_package_html ("image", "image_html", "octave-forge");
## @end example
##
## If you want to include prepared package documentation in html format,
## you have to set @var{options}.package_doc manually with the filename
## of its texinfo source, which must be in the package "doc" directory.
## Contained images are automatically copied if they are at the paths
## specified in the texinfo source relative to the package "doc" directory.
## Additional arguments can be passed to makeinfo using the optional
## field @var{options}.package_doc_options.
##
## It should be noted that the function only works for installed packages.
## @seealso{get_html_options}
## @end deftypefn

function generate_package_html (name = [], outdir = "htdocs", options = struct ())

  ## Check input
  if (isempty (name))
    list = pkg ("list");
    for k = 1:length (list)
      generate_package_html (list{k}.name, outdir, options);
    endfor
    return;
  elseif (isstruct (name))
    desc = name;
    if (isfield (name, "name"))
      packname = desc.name;
    else
      packname = "";
    endif
  elseif (ischar (name))
    packname = name;
    pkg ("load", name);
    desc = (pkg ("describe", name)){1};
  else
    error (["First input must either be the name of a ", ...
            "package, or a structure giving its description."]);
  endif

  ## Get detailed information about the package.
  ##
  ## We don't want a dependency on the struct package for
  ## generate_html, otherwise the following could be:
  ##
  ## list = cell2struct (all_list.', {structcat(1, all_list{}).name}, 1).(packname)
  ##
  ## But probably pkg ("list") should not return a cell array of
  ## structures anyway.
  all_list = pkg ("list");
  list = [];
  for k = 1:length (all_list)
    if (strcmp (all_list{k}.name, packname))
      list = all_list{k};
      break;
    endif
  endfor
  if (isempty (list))
    error ("Couldn't locate package '%s'", packname);
  endif
  depends = struct ();
  for k = 1 : numel (list.depends)
    it_depends = list.depends{k};
    if (isfield (it_depends, "operator") && isfield (it_depends, "version"))
      o = it_depends.operator;
      v = it_depends.version;
      depends.(it_depends.package) = sprintf ("%s %s", o, v);
    else
      depends.(it_depends.package) = "";
    endif
  endfor

  if (isempty (outdir))
    outdir = packname;
  elseif (! ischar (outdir))
    error ("Second input argument must be a string");
  endif

  ## Create output directory if needed
  assert_dir (outdir);

  ## Create package directory if needed
  assert_dir (packdir = fullfile (outdir, packname));

  ## Process input argument 'options'
  if (ischar (options)) || (isstruct (options))
    options = get_html_options (options);
  else
    error ("Third input argument must be a string or a structure");
  endif

  ## Initialize getopt.
  getopt (options, desc);

  ## Function directory
  local_fundir = getopt ("function_dir");
  fundir = fullfile (packdir, local_fundir);


  ## Create function directory if needed
  assert_dir (fundir);

  ## Write easily parsable informational file.

  export = getopt ({"get_pars"});

  l_fields = {"date";
              "author";
              "maintainer";
              "buildrequires";
              "license";
              "url"};

  for field = l_fields.'
    if (isfield (list, field{1}))
      export.(field{1}) = list.(field{1});
    else
      export.(field{1}) = "";
    endif
  endfor

  export.depends = depends;

  export.has_overview = getopt ("include_overview");
  export.has_alphabetical_data = getopt ("include_alpha");
  export.has_short_description = ...
    getopt ("include_package_list_item");
  export.has_news = getopt ("include_package_news");
  export.has_package_doc = ! isempty (getopt ("package_doc"));
  export.has_index = getopt ("include_package_page");
  export.has_license = getopt ("include_package_license");
  export.has_website_files = ! isempty (getopt ("website_files"));
  export.has_demos = getopt ("include_demos");

  json = encode_json_object (export);

  fileprintf (fullfile (packdir, "description.json"),
              "informational file",
              sprintf ("%s\n", json));

  ##################################################
  ## Generate html pages for individual functions ##
  ##################################################

  num_categories = length (desc.provides);
  anchors = implemented = cell (1, num_categories);
  for k = 1:num_categories
    F = desc.provides{k}.functions;
    category = desc.provides{k}.category;

    ## Create a valid anchor name by keeping only alphabetical characters
    anchors{k} = regexprep (category, "[^a-zA-Z]", "_");

    ## For each function in category
    num_functions = length (F);
    implemented{k} = cell (1, num_functions);
    for l = 1:num_functions
      fun = F{l};
      if (fun(1) == "@")
        ## Extract @-directory name from function name
        at_dir = fullfile (fundir, fileparts (fun));
        ## Create directory if needed
        assert_dir (at_dir);
        ## Package root is two level upper in the case of an @-directory
        pkgroot = "../..";
      else
        pkgroot = "..";
      endif
      outname = fullfile (fundir, sprintf ("%s.html", fun));
      try
        __html_help_text__ (outname, struct ("pkgroot", pkgroot,
                                             "name", fun));
        implemented{k}{l} = true;
      catch
        err = lasterror ();
        if (strfind (err.message, "not found"))
          warning ("marking '%s' as not implemented", fun);
          implemented{k}{l} = false;
        else
          rethrow (err);
        endif
      end_try_catch
    endfor
  endfor

  #########################
  ## Write overview file ##
  #########################
  first_sentences = cell (1, num_categories);
  if (getopt ("include_overview"))

    ## Create filename for the overview page
    overview_filename = getopt ("overview_filename");
    overview_filename = strrep (overview_filename, " ", "_");

    fid = fopen (fullfile (packdir, overview_filename), "w");
    if (fid < 0)
      error ("Couldn't open overview file for writing");
    endif

    vpars = struct ("name", packname,
                    "pkgroot", "");
    header = getopt ("overview_header", vpars);
    title  = getopt ("overview_title",  vpars);
    footer = getopt ("overview_footer", vpars);

    fprintf (fid, "%s\n", header);
    fprintf (fid, "<h2 class=\"tbdesc\">%s</h2>\n\n", desc.name);

    fprintf (fid, "  <div class=\"package_description\">\n");
    fprintf (fid, "    %s\n", desc.description);
    fprintf (fid, "  </div>\n\n");

    fprintf (fid, "<p>Select category:  <select name=\"cat\" onchange=\"location = this.options[this.selectedIndex].value;\">\n");
    for k = 1:num_categories
      category = desc.provides{k}.category;
      fprintf (fid, "    <option value=\"#%s\">%s</option>\n", anchors{k}, category);
    endfor
    fprintf (fid, "  </select></p>\n\n");

    ## Generate function list by category
    for k = 1:num_categories
      F = desc.provides{k}.functions;
      category = desc.provides{k}.category;
      fprintf (fid, "  <h3 class=\"category\"><a name=\"%s\">%s</a></h3>\n\n",
               anchors{k}, category);

      first_sentences{k} = cell (1, length (F));

      ## For each function in category
      for l = 1:length (F)
        fun = F{l};
        if (implemented{k}{l})
          try
            ## This will raise an error if the function is undocumented:
            first_sentences{k}{l} = get_first_help_sentence (fun, 200);
          catch
            err = lasterror ();
            if ~ isempty (strfind (err.message, 'not documented'))
              warning (sprintf ("%s is undocumented", fun));
              first_sentences{k}{l} = "Not documented";
            else
              rethrow (err);
            endif
          end_try_catch
          first_sentences{k}{l} = strrep (first_sentences{k}{l}, "\n", " ");

          link = sprintf ("%s/%s.html", local_fundir, fun);
          fprintf (fid, "    <div class=\"func\"><b><a href=\"%s\">%s</a></b></div>\n",
                   link, fun);
          fprintf (fid, "    <div class=\"ftext\">%s</div>\n\n", ...
                   first_sentences{k}{l});
        else
          fprintf (fid, "    <div class=\"func\"><b>%s</b></div>\n", fun);
          fprintf (fid, "    <div class=\"ftext\">Not implemented.</div>\n\n");
        endif
      endfor
    endfor

    fprintf (fid, "\n%s\n", footer);
    fclose (fid);
  endif

################################################
## Write function data for alphabetical lists ##
################################################

  if (getopt ("include_alpha"))

    ## hash name information first, so we needn't go through all names
    ## for each letter
    name_hashes = struct ();
    nfcns = zeros (num_categories, 1); # for generating numeric
                                       # indices later
    for k = 1:num_categories
      F = desc.provides{k}.functions;
      if (k < num_categories)
        nfcns(k + 1) = numel (F);
      endif
      for l = 1:numel (F)
        if (implemented{k}{l})
          fun = F{l};
          if (any (fun == "."))
            ## namespaced function
            initial = lower (fun(1));
            [nsp, fcn] = strsplit (fun, "."){:};
            name_hashes.(["nsp_", initial]).(nsp).(fcn) = [k, l];
          elseif (fun(1) == "@")
            ## class method
            initial = lower (fun(2));
            [class, method] = strsplit (fun, "/"){:};
            name_hashes.(["class_", initial]).(class).(method) = [k, l];
          else
            ## normal function
            initial = lower (fun(1));
            name_hashes.(["fun_", initial]).(fun) = [k, l];
          endif
        endif
      endfor
    endfor
    cum_nfcns = cumsum (nfcns);

    ## directory for function information
    assert_dir (directory = fullfile (outdir, desc.name));
    ## subdirectory for class information
    assert_dir (classes_dir = fullfile (directory, "classes"));
    ## subdirectory for namespace information
    assert_dir (nsps_dir = fullfile (directory, "namespaces"));

    ## flatten by concatenating all categories
    f_s_linear = horzcat (first_sentences{:});

    ## FIXME: Do the php scripts really need, for functions, a file
    ## for each letter, even if the file is empty? Otherwise loop over
    ## fieldnames.
    for letter = "a":"z"

      ## function names
      name_fn = fullfile (directory, ["function_names_", letter]);
      desc_fn = fullfile (directory, ["function_descriptions_", letter]);
      if (isfield (name_hashes, ["fun_", letter]))
        [funs, idx] = sort (fieldnames (name_hashes.(["fun_", letter])));
        pos = vertcat (struct2cell (name_hashes.(["fun_", letter])){idx});
        ## linear positions of functions in 'first_sentences'
        lpos = cum_nfcns(pos(:, 1)) + pos(:, 2);
        fileprintf (name_fn, "alphabet database", "%s\n", funs{:});
        fileprintf (desc_fn, "alphabet database", "%s\n", f_s_linear{lpos});
      else
        ## create empty files
        fileprintf (name_fn, "alphabet database", "");
        fileprintf (desc_fn, "alphabet database", "");
      endif

      ## class names
      if (isfield (name_hashes, ["class_", letter]))
        assert_dir (name_cl = fullfile (classes_dir,
                                        ["class_names_", letter]));
        classes = sort (fieldnames (name_hashes.(["class_", letter])));
        for cid = 1:numel (classes)
          assert_dir (classdir = fullfile (name_cl, classes{cid}));
          mthds = fieldnames (name_hashes.(["class_", letter]). ...
                                          (classes{cid}));
          for mid = 1:numel (mthds)
            mthd_fn = fullfile (classdir, mthds{mid});
            pos = name_hashes.(["class_", letter]). ...
                              (classes{cid}).(mthds{mid});
            fileprintf (mthd_fn, "alphabet database",
                        [first_sentences{pos(1)}{pos(2)}, "\n"]);
          endfor
        endfor
      endif

      ## namespaces
      if (isfield (name_hashes, ["nsp_", letter]))
        assert_dir (name_nsp = fullfile (nsps_dir,
                                        ["namespace_names_", letter]));
        nsps = sort (fieldnames (name_hashes.(["nsp_", letter])));
        for nid = 1:numel (nsps)
          assert_dir (nspdir = fullfile (name_nsp, nsps{nid}));
          fcns = fieldnames (name_hashes.(["nsp_", letter]). ...
                                          (nsps{nid}));
          for fid = 1:numel (fcns)
            fcn_fn = fullfile (nspdir, fcns{fid});
            pos = name_hashes.(["nsp_", letter]). ...
                              (nsps{nid}).(fcns{fid});
            fileprintf (fcn_fn, "alphabet database",
                        [first_sentences{pos(1)}{pos(2)}, "\n"]);
          endfor
        endfor
      endif

    endfor

  endif

  #####################################################
  ## Write short description for forge overview page ##
  #####################################################

  if (getopt ("include_package_list_item"))

    pkg_list_item_filename = getopt ("pkg_list_item_filename");

    vpars = struct ("name", desc.name);
    text = getopt ("package_list_item", vpars);

    fileprintf (fullfile (packdir, pkg_list_item_filename),
                pkg_list_item_filename,
                text);

  endif

  #####################
  ## Write NEWS file ##
  #####################
  if (! getopt ("include_package_news"))
    write_package_news = false;
  else
    ## Read news
    filename = fullfile (list.dir, "packinfo", "NEWS");
    fid = fopen (filename, "r");
    if (fid < 0)
      warning ("generate_package_html: couldn't open NEWS for reading");
      write_package_news = false;
    else
      write_package_news = true;
      news_content = char (fread (fid).');
      fclose (fid);

      ## Open output file
      news_filename = "NEWS.html";

      fid = fopen (fullfile (packdir, news_filename), "w");
      if (fid < 0)
        error ("Couldn't open NEWS file for writing");
      endif

      vpars = struct ("name", desc.name,
                      "pkgroot", "");
      header = getopt ("news_header", vpars);
      title  = getopt ("news_title",  vpars);
      footer = getopt ("news_footer", vpars);

      ## Write output
      fprintf (fid, "%s\n", header);
      fprintf (fid, "<h2 class=\"tbdesc\">NEWS for '%s' Package</h2>\n\n", desc.name);
      fprintf (fid, "<p><a href=\"index.html\">Return to the '%s' package</a></p>\n\n", desc.name);

      fprintf (fid, "<pre>%s</pre>\n\n", insert_char_entities (news_content));

      fprintf (fid, "\n%s\n", footer);
      fclose (fid);
    endif
  endif

  #################################
  ## Write package documentation ##
  #################################

  # Is there a package documentation to be included ?
  write_package_documentation = ! isempty (getopt ("package_doc"));

  if (write_package_documentation)

    [~, doc_fn, doc_ext] = fileparts (getopt ("package_doc"));
    doc_root_dir = fullfile (list.dir, "doc");
    doc_src = fullfile (doc_root_dir, [doc_fn, doc_ext]);
    doc_subdir = "package_doc";
    doc_out_dir = fullfile (packdir, doc_subdir);

    system (sprintf ('mkdir -p %s', doc_out_dir));

    ## Create makeinfo command
    makeinfo_cmd = sprintf ("%s --html -o %s %s", makeinfo_program (),
                            doc_out_dir, doc_src);
    if (! isempty (package_doc_options = getopt ("package_doc_options")))
      makeinfo_cmd = [makeinfo_cmd, ' ', package_doc_options];
    endif

    ## Convert texinfo to HTML using makeinfo
    status = system (makeinfo_cmd);
    if (status == 127)
      error ("Program `%s' not found", makeinfo_program ());
    elseif (status)
      error ("Program `%s' returned failure code %i",
             makeinfo_program (), status);
    endif

    ## Search the name of the main HTML index file.
    package_doc_index = 'index.html';
    if (! exist (fullfile (doc_out_dir, package_doc_index), "file"))
      ## Look for an HTML file with the same name as the texinfo source file
      [~, doc_fn, doc_ext] = fileparts (doc_src);
      package_doc_index = [doc_fn, '.html'];
      if (! exist (fullfile (doc_out_dir, package_doc_index), "file"))
        ## If there is only one file, no hesitation
        html_fn_list = glob (fullfile (doc_out_dir, "*.html"));
        if (length (html_fn_list) == 1)
          [~, doc_fn, doc_ext] = fileparts (html_filenames_temp{1});
          package_doc_index = [doc_fn, doc_ext];
        else
          error ('Unable to determine the root of the HTML manual.');
        endif
      endif
    endif

    ## Read image and css references from generated files and copy images
    filelist = glob (fullfile (doc_out_dir, "*.html"));
    for id = 1 : numel (filelist)
      copy_files ("image", filelist{id}, doc_root_dir, doc_out_dir);
      copy_files ("css", filelist{id}, doc_root_dir, doc_out_dir);
    endfor

  endif

  ######################
  ## Write index file ##
  ######################

  if (getopt ("include_package_page"))

    ## Open output file
    index_filename = "index.html";

    fid = fopen (fullfile (packdir, index_filename), "w");
    if (fid < 0)
      error ("Couldn't open index file for writing");
    endif

    ## Write output
    vpars = struct ("name", desc.name,
                    "pkgroot", "");
    header = getopt ("index_header", vpars);
    title  = getopt ("index_title",  vpars);
    footer = getopt ("index_footer", vpars);

    fprintf (fid, "%s\n", header);
    fprintf (fid, "<h2 class=\"tbdesc\">%s</h2>\n\n", desc.name);

    fprintf (fid, "<table>\n");
    fprintf (fid, "<tr><td rowspan=\"2\" class=\"box_table\">\n");
    fprintf (fid, "<div class=\"package_box\">\n");
    fprintf (fid, "  <div class=\"package_box_header\"></div>\n");
    fprintf (fid, "  <div class=\"package_box_contents\">\n");
    fprintf (fid, "    <table>\n");
    fprintf (fid, "      <tr><td class=\"package_table\">Package Version:</td><td>%s</td></tr>\n",
            list.version);
    fprintf (fid, "      <tr><td class=\"package_table\">Last Release Date:</td><td>%s</td></tr>\n",
             list.date);
    fprintf (fid, "      <tr><td class=\"package_table\">Package Author:</td><td>%s</td></tr>\n",
             insert_char_entities (list.author));
    fprintf (fid, "      <tr><td class=\"package_table\">Package Maintainer:</td><td>%s</td></tr>\n",
             insert_char_entities (list.maintainer));
    fprintf (fid, "      <tr><td class=\"package_table\">License:</td><td><a href=\"COPYING.html\">");
    if (isfield (list, "license"))
      fprintf (fid, "%s</a></td></tr>\n", list.license);
    else
      fprintf (fid, "Read license</a></td></tr>\n");
    endif
    fprintf (fid, "    </table>\n");
    fprintf (fid, "  </div>\n");
    fprintf (fid, "</div>\n");
    fprintf (fid, "</td>\n\n");

    fprintf (fid, "<td>\n");
    vpars = struct ("name", desc.name);
    if (! isempty (link = getopt ("download_link", vpars)))
      fprintf (fid, "<div class=\"download_package\">\n");
      fprintf (fid, "  <table><tr><td>\n");
      fprintf (fid, "    <a href=\"%s\" class=\"download_link\">\n", link);
      fprintf (fid, "      <img src=\"../download.png\" alt=\"Package download icon\"/>\n");
      fprintf (fid, "    </a>\n");
      fprintf (fid, "  </td><td>\n");
      fprintf (fid, "    <a href=\"%s\" class=\"download_link\">\n", link);
      fprintf (fid, "      Download Package\n");
      fprintf (fid, "    </a></td></tr>\n");
      if (! isempty (repository_link = ...
                     getopt ("repository_link", vpars)))
        fprintf (fid, "    <tr><td>\n");
        fprintf (fid, "      <a href=\"%s\" class=\"repository_link\">\n",
                 repository_link);
        fprintf (fid,
                 "        <img src=\"../repository.png\" alt=\"Repository icon\"\></a></td>\n");
        fprintf (fid,
                 "  <td><a href=\"%s\" class=\"repository_link\">",
                 repository_link);
        fprintf (fid, "Repository</a>\n");
        fprintf (fid, "</td></tr>\n");
      endif
      ## The following link will have small text. So capitalize it,
      ## too, and don't put it in parantheses, otherwise it might be
      ## mistaken for a verbal attribute to the link above it.
      if (! isempty (older_versions_download = ...
                     getopt ("older_versions_download", vpars)))
        fprintf (fid, "    <tr><td /><td><a href=\"%s\"\n", older_versions_download);
        fprintf (fid, "     class=\"older_versions_download\">Older versions</a></td></tr>\n");
      end
      fprintf (fid, "  </table>\n");
      fprintf (fid, "</div>\n");
    endif
    fprintf (fid, "</td></tr>\n");
    fprintf (fid, "<tr><td>\n");
    fprintf (fid, "<div class=\"package_function_reference\">\n");
    fprintf (fid, "  <table><tr><td>\n");
    fprintf (fid, "    <a href=\"%s\" class=\"function_reference_link\">\n", overview_filename);    
    fprintf (fid, "      <img src=\"../doc.png\" alt=\"Function reference icon\"/>\n");
    fprintf (fid, "    </a>\n");
    fprintf (fid, "  </td><td>\n");
    fprintf (fid, "    <a href=\"%s\" class=\"function_reference_link\">\n", overview_filename);
    fprintf (fid, "      Function Reference\n");
    fprintf (fid, "    </a>\n");
    fprintf (fid, "  </td></tr>\n");
    if (write_package_documentation)
      link = fullfile (doc_subdir, package_doc_index);
      fprintf (fid, "  <tr><td>\n");
      fprintf (fid, "    <a href=\"%s\" class=\"package_doc\">\n", link);      
      fprintf (fid, "      <img src=\"../manual.png\" alt=\"Package doc icon\"/>\n");
      fprintf (fid, "    </a>\n");      
      fprintf (fid, "  </td><td>\n");
      fprintf (fid, "    <a href=\"%s\" class=\"package_doc\">\n", link);
      fprintf (fid, "      Package Documentation\n");
      fprintf (fid, "    </a>\n");
      fprintf (fid, "  </td></tr>\n");
    endif
    if (write_package_news)
      fprintf (fid, "  <tr><td>\n");
      fprintf (fid, "    <a href=\"NEWS.html\" class=\"news_file\">\n");      
      fprintf (fid, "      <img src=\"../news.png\" alt=\"Package news icon\"/>\n");
      fprintf (fid, "    </a>\n");      
      fprintf (fid, "  </td><td>\n");
      fprintf (fid, "    <a href=\"NEWS.html\" class=\"news_file\">\n");
      fprintf (fid, "      NEWS\n");
      fprintf (fid, "    </a>\n");
      fprintf (fid, "  </td></tr>\n");
    endif
    if (isfield (list, "url")) && (! isempty (list.url))
      index_write_homepage_links (fid, list.url);
    endif
    fprintf (fid, "  </table>\n");
    fprintf (fid, "</div>\n");
    fprintf (fid, "</td></tr>\n");
    fprintf (fid, "</table>\n\n");

    fprintf (fid, "<h3>Description</h3>\n");
    fprintf (fid, "  <div id=\"description_box\">\n")
    fprintf (fid, list.description);
    fprintf (fid, "  </div>\n\n")

    fprintf (fid, "<h3>Details</h3>\n");
    fprintf (fid, "  <table id=\"extra_package_table\">\n");

    if (isfield (list, "depends"))
      fprintf (fid, "    <tr><td>Dependencies: </td><td>\n");

      for [vt, p] = depends
        if (strcmpi (p, "octave"))
          fprintf (fid, "<a href=\"http://www.octave.org\">Octave</a> ");
        else
          fprintf (fid, "<a href=\"../%s/index.html\">%s</a> ", p, p);
        endif
        fprintf (fid, vt);
      endfor
      fprintf (fid, "</td></tr>\n");
    endif

    if (isfield (list, "systemrequirements"))
      fprintf (fid, "    <tr><td>Runtime system dependencies:</td><td>%s</td></tr>\n", list.systemrequirements);
    endif

    if (isfield (list, "buildrequires"))
      fprintf (fid, "    <tr><td>Build dependencies:</td><td>%s</td></tr>\n", list.buildrequires);
    endif

    fprintf (fid, "  </table>\n\n");

    fprintf (fid, "\n%s\n", footer);
    fclose (fid);
  endif

  ########################
  ## Write COPYING file ##
  ########################
  if (getopt ("include_package_license"))

    ## Read license
    filename = fullfile (list.dir, "packinfo", "COPYING");
    fid = fopen (filename, "r");
    if (fid < 0)
      error ("Couldn't open license for reading");
    endif
    copying_contents = char (fread (fid).');
    fclose (fid);

    ## Open output file
    copying_filename = "COPYING.html";

    fid = fopen (fullfile (packdir, copying_filename), "w");
    if (fid < 0)
      error ("Couldn't open COPYING file for writing");
    endif

    vpars = struct ("name", desc.name,
                    "pkgroot", "");
    header = getopt ("copying_header", vpars);
    title  = getopt ("copying_title",  vpars);
    footer = getopt ("copying_footer", vpars);

    ## Write output
    fprintf (fid, "%s\n", header);
    fprintf (fid, "<h2 class=\"tbdesc\">License for '%s' Package</h2>\n\n", desc.name);
    fprintf (fid, "<p><a href=\"index.html\">Return to the '%s' package</a></p>\n\n", desc.name);

    fprintf (fid, "<pre>%s</pre>\n\n", insert_char_entities (copying_contents));

    fprintf (fid, "\n%s\n", footer);
    fclose (fid);
  endif

  ########################
  ## Copy website files ##
  ########################
  if (! isempty (website_files = getopt ("website_files")))
    copyfile (fullfile (fileparts (mfilename ("fullpath")),
                        website_files, "*"),
              outdir, "f");
  endif

endfunction

function copy_files (filetype, file, doc_root_dir, doc_out_dir)

  switch filetype
    case "image"
      pattern = "<(?:img.+?src|object.+?data)=""([^""]+)"".*?>";
    case "css"
      pattern = "<(?:link rel=\"stylesheet\".+?href|object.+?data)=""([^""]+)"".*?>";
    otherwise
      error ("copy_files: invalid file type");
  endswitch

  if ((fid = fopen (file)) < 0)
    error ("Couldn't open %s for reading", file);
  endif
  unwind_protect
    while (! isnumeric (l = fgetl (fid)))
      m = regexp (l, pattern, "tokens");
      for i = 1 : numel (m)
        url = m{i}{1};
        ## exclude external links
        if (isempty (strfind (url, "//")))
          if (! isempty (strfind (url, "..")))
            warning ("not copying %s %s because path contains '..'",
                     filetype, url);
          else
            if (! isempty (imgdir = fileparts (url)) &&
                ! strcmp (imgdir, "./") &&
                ! exist (imgoutdir = fullfile (doc_out_dir, imgdir), "dir"))
              [succ, msg] = mkdir (imgoutdir);
              if (!succ)
                error ("Unable to create directory %s:\n %s", imgoutdir, msg);
              endif
            endif
            if (isempty (glob (src = fullfile (doc_root_dir, url))))
              warning ("%s file %s not present, not copied",
                       filetype, url);
            elseif (! ([status, msg] = copyfile (src,
                                             fullfile (doc_out_dir, url))))
              warning ("could not copy %s file %s: %s", filetype, url, msg);
            endif
          endif
        endif
      endfor
    endwhile
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect

endfunction

function assert_dir (directory)
  if (! exist (directory, "dir"))
    [succ, msg] = mkdir (directory);
    if (! succ)
      error ("Could not create '%s': %s", directory, msg);
    endif
  endif
endfunction

function fileprintf (path, what_file, varargin)
  if (([fid, msg] = fopen (path, "w")) == -1)
    error ("Could not open %s for writing", what_file);
  endif
  unwind_protect
    fprintf (fid, varargin{:});
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect
endfunction

function json = encode_json_object (map, indent = "")

  ## encodes only scalar structures, recursively all values must be
  ## scalar structures, strings, or booleans; adds no final newline

  if ((nf = numel (fns = fieldnames (map))))

    tmpl = strcat (["\n" indent '  "%s": %s'],
                   repmat ([",\n" indent '  "%s": %s'], 1, nf - 1));

  else
    tmpl = "";
  endif

  for id = 1:nf

    if (isstruct (map.(fns{id})))

      map.(fns{id}) = ...
      cstrcat ("\n", encode_json_object (map.(fns{id}), [indent "  "]));

    elseif (isbool (map.(fns{id})))

      if (map.(fns{id}))
        map.(fns{id}) = "true";
      else
        map.(fns{id}) = "false";
      endif

    else

      map.(fns{id}) = cstrcat ('"', map.(fns{id}), '"');

    endif

  endfor

  json = sprintf ([indent "{" tmpl "\n" indent "}"],
                  vertcat (fns.', struct2cell (map).'){});
  
endfunction
